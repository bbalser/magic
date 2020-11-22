defmodule Magic do
  @quoted_term quote do: term

  defstruct [:env, :behaviour, :mock, :functions, :overrides]

  defmacro __using__(opts) do
    quote do
      @before_compile Magic
      @on_definition Magic
      Module.put_attribute(__MODULE__, :magic_opts, unquote(opts))
      Module.register_attribute(__MODULE__, :magic_functions, accumulate: true)
    end
  end

  def __on_definition__(env, :def, name, args, _guards, _body) do
    Module.put_attribute(env.module, :magic_functions, {name, args})
  end

  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    :ok
  end

  defmacro __before_compile__(env) do
    if Mix.env() == :test do
      do_magic(env)
    end
  end

  defp do_magic(env) do
    Module.get_attribute(env.module, :magic_opts, [])
    |> Keyword.put(:env, env)
    |> to_struct()
    |> maybe_generate_behaviour()
    |> generate_mock()
    |> generate_overrides()
    |> to_ast()
  end

  defp to_ast(state) do
    quote do
      if Module.get_attribute(__MODULE__, :behaviour) == [] do
        @behaviour unquote(state.behaviour)
      end

      defoverridable unquote(state.behaviour)

      unquote(state.overrides)
    end
  end

  defp generate_mock(%{mock: nil} = state) do
    %{state | mock: Module.concat(state.env.module, Mock)}
    |> generate_mock()
  end

  defp generate_mock(state) do
    Mox.defmock(state.mock, for: state.behaviour)
    state
  end

  defp generate_overrides(state) do
    functions =
      state.behaviour.behaviour_info(:callbacks)
      |> Enum.map(fn {name, arity} ->
        {name, Macro.generate_arguments(arity, state.env.module)}
      end)

    overrides =
      Enum.map(functions, fn {name, args} ->
        quote do
          def unquote(name)(unquote_splicing(args)) do
            caller_pids =
              case Process.get(:"$callers") do
                nil -> []
                pids when is_list(pids) -> pids
              end

            all_callers = [self() | caller_pids]

            case Mox.Server.fetch_fun_to_dispatch(
                   all_callers,
                   {unquote(state.mock), unquote(name), unquote(length(args))}
                 ) do
              :no_expectation ->
                super(unquote_splicing(args))

              _ ->
                apply(unquote(state.mock), unquote(name), unquote(args))
            end
          end
        end
      end)

    %{state | overrides: overrides}
  end

  defp maybe_generate_behaviour(%{behaviour: nil, env: env} = state) do
    behaviour = Module.concat(env.module, Behaviour)
    functions = Module.get_attribute(env.module, :magic_functions, [])

    contents =
      Enum.map(functions, fn {name, args} ->
        terms = Enum.map(args, fn _ -> @quoted_term end)

        quote do
          @callback unquote(name)(unquote_splicing(terms)) :: term
        end
      end)

    Module.create(behaviour, contents, Macro.Env.location(__ENV__))

    %{state | behaviour: behaviour}
  end

  defp maybe_generate_behaviour(state), do: state

  defp to_struct(opts) do
    struct!(__MODULE__, opts)
  end
end
