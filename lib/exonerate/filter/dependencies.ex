defmodule Exonerate.Filter.Dependencies do
  @moduledoc false

  alias Exonerate.Cache
  alias Exonerate.Tools

  defmacro filter_from_cached(name, pointer, opts) do
    name
    |> Cache.fetch!()
    |> JsonPointer.resolve!(pointer)
    |> Enum.map(&make_dependencies(&1, name, pointer, opts))
    |> Enum.unzip()
    |> build_code(name, pointer)
    |> Tools.maybe_dump(opts)
  end

  defp make_dependencies({key, schema}, name, pointer, opts) do
    call =
      pointer
      |> JsonPointer.traverse([key, ":entrypoint"])
      |> Tools.pointer_to_fun_name(authority: name)

    {quote do
       :ok <- unquote(call)(content, path)
     end, accessory(call, key, schema, name, pointer, opts)}
  end

  defp build_code({prongs, accessories}, name, pointer) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    quote do
      defp unquote(call)(content, path) do
        with unquote_splicing(prongs) do
          :ok
        end
      end

      unquote(accessories)
    end
  end

  defp accessory(call, key, schema, _name, pointer, _opts) when is_list(schema) do
    prongs =
      Enum.with_index(schema, fn
        dependent_key, index ->
          schema_pointer =
            pointer
            |> JsonPointer.traverse([key, "#{index}"])
            |> JsonPointer.to_uri()

          quote do
            :ok <-
              if is_map_key(content, unquote(dependent_key)) do
                :ok
              else
                require Exonerate.Tools
                Exonerate.Tools.mismatch(content, unquote(schema_pointer), path)
              end
          end
      end)

    quote do
      defp unquote(call)(content, path) when is_map_key(content, unquote(key)) do
        with unquote_splicing(prongs) do
          :ok
        end
      end

      defp unquote(call)(content, path), do: :ok
    end
  end

  defp accessory(call, key, schema, name, pointer, opts)
       when is_map(schema) or is_boolean(schema) do
    pointer = JsonPointer.traverse(pointer, key)
    inner_call = Tools.pointer_to_fun_name(pointer, authority: name)

    quote do
      defp unquote(call)(content, path) when is_map_key(content, unquote(key)) do
        unquote(inner_call)(content, path)
      end

      defp unquote(call)(content, path), do: :ok

      require Exonerate.Context
      Exonerate.Context.from_cached(unquote(name), unquote(pointer), unquote(opts))
    end
  end
end
