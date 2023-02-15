defmodule Exonerate.Type.Number do
  @moduledoc false

  # note this module ONLY implements "float".  If something has the "number" type declaration
  # it will implement both Number and Integer, this is handled at the Context level.

  alias Exonerate.Combining
  alias Exonerate.Tools

  @modules Combining.merge(%{
             "maximum" => Exonerate.Filter.Maximum,
             "minimum" => Exonerate.Filter.Minimum,
             "exclusiveMaximum" => Exonerate.Filter.ExclusiveMaximum,
             "exclusiveMinimum" => Exonerate.Filter.ExclusiveMinimum
           })

  @filters Map.keys(@modules)

  def filter(schema, name, pointer) do
    filters =
      schema
      |> Map.take(@filters)
      |> Enum.map(&filter_for(&1, name, pointer))

    call = Tools.pointer_to_fun_name(pointer, authority: name)

    quote do
      defp unquote(call)(content, path) when is_float(content) do
        with unquote_splicing(filters) do
          :ok
        end
      end
    end
  end

  defp filter_for({filter, _}, name, pointer) do
    call =
      pointer
      |> JsonPointer.traverse(Combining.adjust(filter))
      |> Tools.pointer_to_fun_name(authority: name)

    quote do
      :ok <- unquote(call)(content, path)
    end
  end

  def accessories(schema, name, pointer, opts) do
    for filter_name <- @filters,
        is_map_key(schema, filter_name),
        not Combining.filter?(filter_name) do
      module = @modules[filter_name]
      pointer = JsonPointer.traverse(pointer, filter_name)

      quote do
        require unquote(module)
        unquote(module).filter_from_cached(unquote(name), unquote(pointer), unquote(opts))
      end
    end
  end
end
