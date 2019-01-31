defmodule Mix.Tasks.Exonerate.BuildTests do
  use Mix.Task
  require Logger

  @testdir "test/JSON-Schema-Test-Suite/tests/draft7"
  @destdir "test/automated"
  @ignore ["definitions.json", "refRemote.json"]
  @banned %{
    "multipleOf" => ["by number", "by small number"],
    "ref" => ["escaped pointer ref", "nested refs",
      "ref overrides any sibling keywords",
      "$ref to boolean schema true", "$ref to boolean schema false",
      "Recursive references between schemas", "remote ref, containing refs itself"]
  }

  @impl true
  @spec run([String.t]) :: :ok
  def run(_) do
    File.rm_rf!(@destdir)
    File.mkdir_p!(@destdir)
    @testdir
    |> File.ls!
    |> Enum.reject(&(&1 in @ignore))
    |> Enum.reject(&(File.dir?(testdir(&1))))
    |> Stream.map(&{Path.basename(&1, ".json"), testdir(&1)})
    |> Stream.map(&json_to_exmap/1)
    |> Stream.map(&exmap_to_macro/1)
    |> Stream.map(fn {t, m} -> {t, Macro.to_string(m, &ast_xform/2)} end)
    |> Stream.map(&format_string/1)
    |> Enum.map(&send_to_file/1)
    :ok
  end

  @spec format_string({String.t, String.t})::{String.t, iodata}
  defp format_string({t, m}) do
    {t, Code.format_string!(m, locals_without_parens: [defschema: :*])}
  end

  def send_to_file({title, m}) do
    title
    |> destdir
    |> File.write!(m)
  end

  @noparen [:defmodule, :use, :describe, :test, :defschema, :import, :assert]

  @spec ast_xform({atom, any, any}, String.t) :: String.t
  def ast_xform({atom, _, _}, str) when atom in @noparen do
    [head | rest] = String.split(str, "\n")
    parts = Regex.named_captures(~r/\((?<title>.*)\)(?<rest>.*)/, head)
    Atom.to_string(atom) <>
    " " <> parts["title"] <>
    parts["rest"] <> "\n" <> Enum.join(rest, "\n")
  end
  def ast_xform(_, str), do: str

  def testdir(v), do: Path.join(@testdir, v)
  def destdir(v), do: Path.join(@destdir, Path.basename(v, ".json") <> "_test.exs")

  def json_to_exmap({title, jsonfile}) do
    {title,
     jsonfile
     |> File.read!
     |> Jason.decode!}
  end

  def atom_to_module(m), do: Module.concat([m])

  def exmap_to_macro({title, testlist}) do

    modulename = title
    |> String.capitalize
    |> Kernel.<>("Test")
    |> String.to_atom
    |> atom_to_module

    curated_list =
    Enum.reject(testlist, &filter_banned(title, &1))

    schemas = curated_list
    |> Enum.with_index
    |> Enum.map(&module_code/1)

    descriptions = curated_list
    |> Enum.with_index
    |> Enum.map(&description_code/1)

    {title,
    quote do
      defmodule unquote(modulename) do
        use ExUnit.Case, async: true

        defmodule Schemas do
          import Exonerate
          unquote_splicing(schemas)
        end

        unquote_splicing(descriptions)
      end
    end}
  end

  def module_code({description_map, index}) do

    schema_atom = String.to_atom("schema#{index}")

    schema_content = description_map
    |> Map.get("schema")
    |> Jason.encode!

    quote do
      defschema [{unquote(schema_atom), unquote(schema_content)}]
    end
  end

  def description_code({description_map, index}) do
    description_title = description_map["description"]
    tests = Enum.map(description_map["tests"], &test_code(&1, index))

    quote do
      describe unquote(description_title) do
        unquote_splicing(tests)
      end
    end
  end

  def test_code(test_map, index) do
    test_title = test_map["description"]
    test_data = test_map
    |> Map.get("data")
    |> Macro.escape
    schema_name = String.to_atom("schema#{index}")

    if test_map["valid"] do
      quote do
        test unquote(test_title) do
          assert :ok = Schemas.unquote(schema_name)(unquote(test_data))
        end
      end
    else
      quote do
        test unquote(test_title) do
          assert {:mismatch, _} = Schemas.unquote(schema_name)(unquote(test_data))
        end
      end
    end
  end

  defp filter_banned(title, description) do
    @banned[title] && description["description"] in @banned[title]
  end
end
