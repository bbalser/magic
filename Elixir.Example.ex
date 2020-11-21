defmodule Example do
  def sub(a, b) do
    :erlang.-(a, b)
  end

  def add(a, b) do
    :erlang.+(a, b)
  end
end