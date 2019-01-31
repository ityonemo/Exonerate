defmodule Exonerate.Reference do

  alias Exonerate.Method

  @type defblock :: Exonerate.defblock

  @spec match(String.t, atom)::[defblock]
  def match(ref, method) do

    called_method = method
    |> Method.root
    |> Method.jsonpath_to_method(ref)

    IO.puts("ref requested for #{called_method}")
    [quote do
      defp unquote(method)(val) do
        unquote(called_method)(val)
      end
    end]
  end
end
