defmodule :"const with true does not match 1-gpt-3.5" do
  def validate(object) when object === true do
    :ok
  end

  def validate(_) do
    :error
  end
end