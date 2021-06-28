defmodule Exonerate.Validation do
  alias Exonerate.Type

  @enforce_keys [:path]

  @default_types Map.new(~w(
    array
    boolean
    integer
    null
    number
    object
    string
  )a, &{&1, []})

  @behaviour Access
  defstruct @enforce_keys ++ [
    guards: [],
    calls: %{},
    collection_calls: %{},
    children: [],
    accumulator: %{},
    types: @default_types
  ]

  @type t :: %__MODULE__{
    path: Path.t,
    guards: [Macro.t],
    calls: %{Type.t => [Macro.t]},
    collection_calls: %{Type.t => [Macro.t]},
    children: [Macro.t],
    accumulator: %{atom => boolean},
    # compile-time optimization
    types: %{Type.t => []},
  }

  @impl true
  @spec get_and_update(t, atom, (atom -> :pop | {any, any})) :: {any, t}
  defdelegate get_and_update(val, k, v), to: Map
  @impl true
  @spec fetch(t, atom) :: :error | {:ok, any}
  defdelegate fetch(val, key), to: Map
  @impl true
  @spec pop(t, atom) :: {any, t}
  defdelegate pop(val, key), to: Map

  @reserved_keys ~w($schema $id title description default examples)

  def from_schema(true, schema_path) do
    fun = Exonerate.path(schema_path)
    quote do
      defp unquote(fun)(_, _), do: :ok
    end
  end
  def from_schema(false, schema_path) do
    fun = Exonerate.path(schema_path)
    quote do
      defp unquote(fun)(value, path) do
        Exonerate.mismatch(value, path)
      end
    end
  end
  def from_schema(schema, schema_path) when is_map(schema) do
    fun = Exonerate.path(schema_path)

    validation = schema
    |> Enum.reject(&(elem(&1, 0) in @reserved_keys))
    |> Enum.sort(&tag_reorder/2)
    |> Enum.reduce(%__MODULE__{path: schema_path}, fn
      {k, v}, so_far ->
        filter_for(k).append_filter(v, so_far)
    end)

    active_types = Map.keys(validation.types)

    {calls!, types_left} = Enum.flat_map_reduce(active_types, active_types, fn type, types_left ->
      if is_map_key(validation.calls, type) or is_map_key(validation.collection_calls, type) do
        guard = Exonerate.Type.guard(type)
        calls = validation.calls[type]
        |> List.wrap
        |> Enum.reverse
        |> Enum.map(&quote do unquote(&1)(value, path) end)

        collection_calls = validation.collection_calls[type]
        |> List.wrap
        |> Enum.reverse
        |> Enum.map(&quote do acc = unquote(&1)(unit, acc, path) end)

        collection_validation = case type do
          _ when collection_calls == [] -> quote do end
          :object ->
            quote do
              Enum.each(value, fn unit ->
                acc = false
                unquote_splicing(collection_calls)
                acc
              end)
            end
          :array ->
            quote do
              require Exonerate.Filter.MaxItems
              require Exonerate.Filter.MinItems
              require Exonerate.Filter.Contains

              acc =
                Exonerate.Filter.MaxItems.wrap(
                  unquote(schema["maxItems"]),
                  value
                  |> Enum.with_index
                  |> Enum.reduce(unquote(Macro.escape(validation.accumulator)), fn unit, acc ->
                    unquote_splicing(collection_calls)
                    acc
                  end), value, path)

              # special case for MinItems
              Exonerate.Filter.MinItems.postprocess(unquote(schema["minItems"]), acc, value, path)
              Exonerate.Filter.Contains.postprocess(unquote(schema["contains"]), acc, value, path)
            end
        end

        {[quote do
           defp unquote(fun)(value, path) when unquote(guard)(value) do
             unquote_splicing(calls)
             unquote(collection_validation)
             :ok
           end
         end],
         types_left -- [type]}
      else
        {[], types_left}
      end
    end)

    calls! = if types_left == [] do
      calls!
    else
      calls! ++ [quote do
        defp unquote(fun)(_value, _path), do: :ok
      end]
    end

    quote do
      unquote_splicing(validation.guards)
      unquote_splicing(calls!)
      unquote_splicing(validation.children)
    end
  end

  defp tag_reorder(a, a), do: true
  # type, enum to the top, additionalItems and additionalProperties to the bottom
  defp tag_reorder({"type", _}, _), do: true
  defp tag_reorder(_, {"type", _}), do: false
  defp tag_reorder({"enum", _}, _), do: true
  defp tag_reorder(_, {"enum", _}), do: false
  defp tag_reorder({"additionalItems", _}, _), do: false
  defp tag_reorder(_, {"additionalItems", _}), do: true
  defp tag_reorder({"additionalProperties", _}, _), do: false
  defp tag_reorder(_, {"additionalProperties", _}), do: true
  defp tag_reorder(a, b), do: a >= b

  defp filter_for(key) do
    Module.concat(Exonerate.Filter, capitalize(key))
  end

  defp capitalize(<<f::binary-size(1), rest::binary>>) do
    String.upcase(f) <> rest
  end

end
