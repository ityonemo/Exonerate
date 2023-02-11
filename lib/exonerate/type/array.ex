defmodule Exonerate.Type.Array do
  alias Exonerate.Tools

  @modules %{
    "items" => Exonerate.Filter.Items,
    "contains" => Exonerate.Filter.Contains
  }

  @filters Map.keys(@modules)

  # TODO: consider making a version where we don't bother indexing, if it's not necessary.

  def filter(schema, name, pointer) do
    subschema = JsonPointer.resolve!(schema, pointer)
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    case Map.take(subschema, @filters) do
      empty when map_size(empty) === 0 ->
        quote do
          defp unquote(call)(content, _path) when is_list(content) do
            :ok
          end
        end

      _ ->
        class = class_for(subschema)
        filters = filter_calls(subschema, class, name, pointer)

        quote do
          defp unquote(call)(content, path) when is_list(content) do
            content
            |> Enum.reduce_while(unquote(initializer_for(class, pointer)), fn
              item, unquote(accumulator_for(class)) ->
                with unquote_splicing(filters) do
                  unquote(continuation_for(class))
                else
                  halt -> {:halt, {halt, []}}
                end
            end)
            |> elem(0)
          end
        end
    end
  end

  defp class_for(schema) do
    schema
    |> Map.take(@filters)
    |> Map.keys()
    |> case do
      ["contains"] -> :contains
      ["items"] -> :items
      [] -> nil
    end
  end

  defp initializer_for(class, pointer) do
    case class do
      # note that "contains" is inverted, we'll generate the error first
      # and then halt on :ok
      :contains ->
        schema_pointer =
          pointer
          |> JsonPointer.traverse("contains")
          |> JsonPointer.to_uri()

        quote do
          require Exonerate.Tools
          {Exonerate.Tools.mismatch(content, unquote(schema_pointer), path), []}
        end

      :items ->
        {:ok, 0}

      nil ->
        :ok
    end
  end

  defp accumulator_for(class) do
    case class do
      :contains ->
        quote do
          error
        end

      :items ->
        quote do
          {:ok, index}
        end

      _ ->
        quote do
          _
        end
    end
  end

  defp continuation_for(class) do
    case class do
      :contains ->
        quote do
          {:cont, error}
        end

      :items ->
        quote do
          {:cont, {:ok, index + 1}}
        end

      nil ->
        {:cont, {:ok, []}}
    end
  end

  defp filter_calls(schema, class, name, pointer) do
    case Map.take(schema, @filters) do
      empty when empty === %{} ->
        []

      filters ->
        build_filters(filters, class, name, pointer)
    end
  end

  defp build_filters(filters, class, name, pointer) do
    Enum.map(filters, &filter_for(&1, class, name, pointer))
  end

  defp filter_for({"items", list}, _class, name, pointer) when is_list(list) do
    call =
      pointer
      |> JsonPointer.traverse("items")
      |> Tools.pointer_to_fun_name(authority: name)

    quote do
      :ok <- unquote(call)(item, index, Path.join(path, "#{index}"))
    end
  end

  defp filter_for({"items", _}, _class, name, pointer) do
    call =
      pointer
      |> JsonPointer.traverse("items")
      |> Tools.pointer_to_fun_name(authority: name)

    quote do
      :ok <- unquote(call)(item, Path.join(path, "#{index}"))
    end
  end

  defp filter_for({"contains", _}, :contains, name, pointer) do
    call =
      pointer
      |> JsonPointer.traverse("contains")
      |> Tools.pointer_to_fun_name(authority: name)

    quote do
      {:error, _} <- unquote(call)(item, Path.join(path, ":any"))
    end
  end

  def accessories(schema, name, pointer, opts) do
    for filter_name <- @filters, Map.has_key?(schema, filter_name) do
      list_accessory(filter_name, schema, name, pointer, opts)
    end
  end

  defp list_accessory(filter_name, _schema, name, pointer, opts) do
    module = @modules[filter_name]
    pointer = JsonPointer.traverse(pointer, filter_name)

    quote do
      require unquote(module)
      unquote(module).filter_from_cached(unquote(name), unquote(pointer), unquote(opts))
    end
  end
end
