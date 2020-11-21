defmodule Example2.Interface do
  @callback multiply(integer, integer) :: integer
end

defmodule Example2 do
  use Magic, behaviour: Example2.Interface, mock: Example2Mock

  @behaviour Example2.Interface

  @impl true
  def multiply(a, b) do
    a * b
  end
end
