defmodule Exonerate.Context do
  @moduledoc false

  # a context is the representation of "parsing json at a given location"

  alias Exonerate.Cache
  alias Exonerate.Tools
  alias Exonerate.Type

  defmacro from_cached(name, pointer, opts) do
    name
    |> Cache.fetch!()
    |> JsonPointer.resolve!(pointer)
    |> to_quoted_function(name, pointer, opts)
    |> Tools.maybe_dump(opts)
  end

  # don't normally use the brackted alias format but it makes sense here.
  alias Exonerate.Type.{Array, Boolean, Integer, Null, Number, Object, String}

  @filter_map %{
    "array" => Array,
    "boolean" => Boolean,
    "integer" => Integer,
    "null" => Null,
    "number" => Number,
    "object" => Object,
    "string" => String
  }

  defp to_quoted_function(true, name, pointer, _opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    quote do
      @compile {:inline, [{unquote(call), 2}]}
      defp unquote(call)(content, _path) do
        :ok
      end
    end
  end

  defp to_quoted_function(false, name, pointer, _opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)
    schema_pointer = JsonPointer.to_uri(pointer)

    quote do
      @compile {:inline, [{unquote(call), 2}]}
      defp unquote(call)(content, path) do
        require Exonerate.Tools
        Exonerate.Tools.mismatch(content, unquote(schema_pointer), path)
      end
    end
  end

  # metadata
  defp to_quoted_function(schema = %{"title" => title}, name, pointer, opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    rest = schema
    |> Map.delete("title")
    |> to_quoted_function(name, pointer, opts)

    quote do
      defp unquote(call)(:title, _), do: unquote(title)

      unquote(rest)
    end
  end

  defp to_quoted_function(schema = %{"description" => title}, name, pointer, opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    rest = schema
    |> Map.delete("description")
    |> to_quoted_function(name, pointer, opts)

    quote do
      defp unquote(call)(:description, _), do: unquote(title)

      unquote(rest)
    end
  end

  defp to_quoted_function(schema = %{"examples" => title}, name, pointer, opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    rest = schema
    |> Map.delete("examples")
    |> to_quoted_function(name, pointer, opts)

    quote do
      defp unquote(call)(:examples, _), do: unquote(title)

      unquote(rest)
    end
  end

  defp to_quoted_function(schema = %{"default" => title}, name, pointer, opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    rest = schema
    |> Map.delete("default")
    |> to_quoted_function(name, pointer, opts)

    quote do
      defp unquote(call)(:default, _), do: unquote(title)

      unquote(rest)
    end
  end

  # intercept consts
  defp to_quoted_function(schema = %{"const" => const}, name, pointer, opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    const_pointer =
      pointer
      |> JsonPointer.traverse("const")
      |> JsonPointer.to_uri()

    rest_filter =
      schema
      |> Map.delete("const")
      |> to_quoted_function(name, pointer, Keyword.merge(opts, type: typeof(const)))

    value = Macro.escape(const)

    quote do
      defp unquote(call)(content, path) when content !== unquote(value) do
        require Exonerate.Tools
        Exonerate.Tools.mismatch(content, unquote(const_pointer), path)
      end

      unquote(rest_filter)
    end
  end

  # intercept enums
  defp to_quoted_function(schema = %{"enum" => enum}, name, pointer, opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    enum_pointer =
      pointer
      |> JsonPointer.traverse("enum")
      |> JsonPointer.to_uri()

    types =
      enum
      |> Enum.map(&typeof/1)
      |> Enum.uniq()

    rest_filter =
      schema
      |> Map.delete("enum")
      |> to_quoted_function(name, pointer, Keyword.merge(opts, type: types))

    values = Macro.escape(enum)

    quote do
      defp unquote(call)(content, path) when content not in unquote(values) do
        require Exonerate.Tools
        Exonerate.Tools.mismatch(content, unquote(enum_pointer), path)
      end

      unquote(rest_filter)
    end
  end

  defp to_quoted_function(schema = %{"type" => type_or_types}, name, pointer, opts) do
    call = Tools.pointer_to_fun_name(pointer, authority: name)

    type_filters =
      type_or_types
      |> List.wrap()
      |> Enum.map(&Type.module(&1).filter(schema, name, pointer))

    accessories =
      type_or_types
      |> List.wrap()
      |> Enum.flat_map(&Type.module(&1).accessories(schema, name, pointer, opts))

    schema_pointer =
      pointer
      |> JsonPointer.traverse("type")
      |> JsonPointer.to_uri()

    quote do
      unquote(type_filters)

      defp unquote(call)(content, path) do
        require Exonerate.Tools
        Exonerate.Tools.mismatch(content, unquote(schema_pointer), path)
      end

      unquote(accessories)
    end
  end

  @all_types ~w(string object array number integer boolean null)

  defp to_quoted_function(schema, name, pointer, opts) when is_map(schema) do
    internal_types = schema
    |> Map.get(:type, @all_types)
    |> List.wrap
    |> MapSet.new

    type = opts
    |> Keyword.get(:type, @all_types)
    |> List.wrap
    |> MapSet.new()
    |> MapSet.intersection(internal_types)
    |> Enum.to_list

    schema
    |> Map.put("type", type)
    |> to_quoted_function(name, pointer, Keyword.drop(opts, [:type]))
  end

  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_map(value), do: "object"
  defp typeof(value) when is_list(value), do: "array"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_number(value), do: "number"
  defp typeof(value) when is_boolean(value), do: "boolean"
  defp typeof(value) when is_nil(value), do: "null"
end
