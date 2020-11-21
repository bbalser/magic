defmodule MagicTest do
  use ExUnit.Case

  import Mox

  setup :verify_on_exit!

  defmodule Stubber do
    @behaviour Example.Behaviour

    def add(_, _) do
      :stubbed
    end

    def sub(_, _) do
      :stubbed
    end
  end

  test "real" do
    assert Example.add(1, 2) == 3
  end

  test "mock" do
    test = self()
    Example.Mock
    |> stub(:add, fn a, b ->
      send(test, {:add, a, b})
      :ok
    end)

    assert Example.add(1,2) == :ok
    assert_receive {:add, 1, 2}

    assert 1 == Example.sub(3, 2)
  end

  test "with custom behaviour" do
    assert Example2.multiply(2, 2) == 4

    Example2Mock
    |> stub(:multiply, fn _, _ ->
      :ok
    end)

    assert Example2.multiply(2, 2) == :ok
  end

  test "stub_with" do
    assert 2 == Example.add(1, 1)
    stub_with(Example.Mock, Stubber)

    assert :stubbed == Example.add(1, 1)
  end

end
