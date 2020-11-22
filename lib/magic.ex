defmodule Magic do
  @quoted_term quote do: term

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
    opts = Module.get_attribute(env.module, :magic_opts, [])

    behaviour = get_behaviour(env, opts)
    mock = get_mock(env, opts)
    Mox.defmock(mock, for: behaviour)

    overrides = generate_overrides(env, opts, mock)

    quote do
      if Module.get_attribute(__MODULE__, :behaviour) == [] do
        @behaviour unquote(behaviour)
      end

      defoverridable unquote(behaviour)

      unquote(overrides)
    end
  end

  defp generate_overrides(env, opts, mock) do
    functions = get_functions(env, opts)

    Enum.map(functions, fn {name, args} ->
      quote do
        def unquote(name)(unquote_splicing(args)) do
          all_callers = [self() | Magic.caller_pids()]

          case Mox.Server.fetch_fun_to_dispatch(
                 all_callers,
                 {unquote(mock), unquote(name), unquote(length(args))}
               ) do
            :no_expectation ->
              super(unquote_splicing(args))

            _ ->
              apply(unquote(mock), unquote(name), unquote(args))
          end
        end
      end
    end)
  end

  defp get_mock(env, opts) do
    case Keyword.has_key?(opts, :mock) do
      true -> Keyword.get(opts, :mock)
      false -> Module.concat(env.module, Mock)
    end
  end

  defp get_behaviour(env, opts) do
    case Keyword.has_key?(opts, :behaviour) do
      true ->
        Keyword.get(opts, :behaviour)

      false ->
        functions = get_functions(env, opts)
        generate_behaviour(env.module, functions)
    end
  end

  defp get_functions(env, opts) do
    case Keyword.has_key?(opts, :behaviour) do
      true ->
        behaviour = Keyword.get(opts, :behaviour)

        behaviour.behaviour_info(:callbacks)
        |> Enum.map(fn {name, arity} ->
          {name, Macro.generate_arguments(arity, env.module)}
        end)

      false ->
        Module.get_attribute(env.module, :magic_functions, [])
    end
  end

  defp generate_behaviour(module, functions) do
    behaviour = Module.concat(module, Behaviour)

    contents =
      Enum.map(functions, fn {name, args} ->
        terms = Enum.map(args, fn _ -> @quoted_term end)

        quote do
          @callback unquote(name)(unquote_splicing(terms)) :: term
        end
      end)

    Module.create(behaviour, contents, Macro.Env.location(__ENV__))

    behaviour
  end

  def caller_pids do
    case Process.get(:"$callers") do
      nil -> []
      pids when is_list(pids) -> pids
    end
  end
end
