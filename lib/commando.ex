defmodule Commando do
  alias Commando.State
  alias Commando.Help

  @moduledoc """
  Command line parser with default values, useful help messages, and other features.

  Uses OptionParser for parsing, and extends it with:

    - Simple and informative help messages
    - Default values for switches
    - Ability to specify required switches
    - Descriptive error messages
  """
  @type switch_type :: :boolean | :count | :integer | :float | :string
  @type conf :: {:required, boolean()} | {:alias, atom()} | {:default, any()}
  @type conf_list :: [conf]
  @type parse_result :: [{atom(), any()}]

  @doc ~S"""
  Creates a new Commando instance.

  ## Examples

      iex> Commando.create("app").app_name
      "app"

      iex> Commando.create("app", "Doc test app").app_description
      "Doc test app"

      iex> Commando.create("app", "Doc test app", "mix run").example
      "mix run"
  """
  @spec create(String.t, String.t, String.t) :: State.t
  def create(name, description \\ "", example \\ "") do
    %State{app_name: name,
           app_description: description,
           example: example}
  end

  @doc """
  Add a standardized help-message switch (--help, -h) to the Commando instance.

  ## Usage

  The application should check the result of `Commando.parse/2` to verify if
  this switch is true. If so, it should show the `Commando.help_message/1` and
  exit.
  """
  @spec with_help(State.t) :: State.t
  def with_help(commando) do
    commando |> with_switch(:help, :boolean, "Print help message", alias: :h)
  end

  @doc """
  Add a switch to a Commando instance.

  Returns a new Commando instance containing the switch.

  ## Description

  The description will be shown for the switch in the help message generated by
  `Commando.help_message/1`.

  ## Switch Types

  The available switch types are `:boolean`, `:count`, `:integer`, `:float`, `:string`.

  The following switches types take no arguments:
    * `:boolean` - sets the value to `true` when given (see also the
      "Negation switches" section below)
    * `:count` - counts the number of times the switch is given

  The following switches take one argument:
    * `:integer` - parses the value as an integer
    * `:float` - parses the value as a float
    * `:string` - parses the value as a string

  For more information on available switch types, see https://hexdocs.pm/elixir/OptionParser.html#parse/2

  ## Configuration

  `conf` is a list of configuration keywords. The following condfigurations are
  available:

  * `default: any` - If switch is not specified, it will recieve this default value.
  * `alias: atom` - An alias for this switch. e.g. for `:data` you might
    pass `alias: :d`, you can then on the command line use `--data` or `-d`.
  * `required: boolean` - If true, `Commando.parse/2` will return an error if
    this switch is not present in `args`.

  ## Examples

      iex> Commando.create("test_app", "Test app", "mix run") |>
      ...>   Commando.with_switch(:path, :string, "Path", required: true, alias: :p, default: "path/")
      %Commando.State{aliases: [p: :path], app_description: "Test app",
       app_name: "test_app", defaults: [path: "path/"],
       descriptions: [path: "Path"], example: "mix run", required: [:path],
       switches: [path: :string]}

  """
  @spec with_switch(State.t, atom(), State.switch_type, String.t, conf_list) :: State.t
  def with_switch(commando, switch, type, description, conf \\ []) do
    commando
    |> State.add_switch(switch, type)
    |> State.add_description(switch, description)
    |> add_configurations(switch, conf)
  end

  @doc ~S"""
  Parse command line arguments.

  Returns one of:

  * `{:help, message}` - If you added the help swith using `Commando.with_help/1`
    and `--help` or `-h` switches were present. `message` contains the formatted
    help message to show.
  * `{:ok, result}` - If command line args were parsed successfully and all
    required arguments were present. `result` is a keyword list mapping switches
    to their parsed values.
  * `{:error, reason}` - If invalid flags were supplied, or a required argument
    was missing.


  ## Examples

      iex> Commando.create("app") |> Commando.with_switch(:path, :string, "Path") |> Commando.parse(["--path", "abc"])
      {:ok, [path: "abc"]}

      iex> import Commando
      iex> create("app") |> with_switch(:path, :string, "Path", alias: :p) |> parse(["-p", "abc"])
      {:ok, [path: "abc"]}

      iex> import Commando
      iex> create("app") |> parse(["--path", "abc"])
      {:error, "Unknown options: --path"}

      iex> import Commando
      iex> create("app") |> with_switch(:foo, :boolean, "") |> parse(["--foo"])
      {:ok, [foo: true]}

      iex> import Commando
      iex> create("app") |> with_switch(:foo, :count, "", alias: :f) |> parse(["--foo", "-f", "-f"])
      {:ok, [foo: 3]}

      iex> import Commando
      iex> create("app") |> with_switch(:foo, :integer, "") |> parse(["--foo", "12"])
      {:ok, [foo: 12]}

      iex> import Commando
      iex> create("app") |> with_switch(:foo, :integer, "") |> parse(["--foo", "bar"])
      {:error, "Unknown options: --foo"}
  """
  @spec parse(State.t, [String.t]) :: {:ok, parse_result} | :help | {:error, String.t}
  def parse(commando, args) do
    opts = [strict: commando.switches, aliases: commando.aliases]
    case args |> OptionParser.parse(opts)
              |> missing_switches(commando)
              |> check_help_flag() do
      :help ->
        {:help, help_message(commando)}
      {result, [], []} ->
        {:ok, result |> result_add_defaults(commando)}
      {_, [], missing} ->
        {:error, Help.build_missing_options(missing)}
      {_, invalid, _} ->
        {:error, Help.build_invalid_options(invalid)}
    end
  end

  @doc ~S"""
  Returns a help message for the Commando instance, to be displayed with e.g.
  `IO.puts`.

  Below is an example help message:

  ```
  demo - Short demo app

  Arguments:
    --path, -p : (Required) Some path (Default: "path")
    --help : Print help message

  Example: mix run
  ```

  ## Examples

      iex> Commando.create("demo", "Short demo app", "mix run") |>
      ...>  Commando.with_help() |>
      ...>  Commando.with_switch(:path, :string, "Some path", required: true, alias: :p, default: "path") |>
      ...>  Commando.help_message()
      "demo - Short demo app\n\nArguments:\n  --path, -p : (Required) Some path (Default: \"path\")\n  --help, -h : Print help message\n\nExample: mix run"
  """
  @spec help_message(State.t) :: String.t
  def help_message(commando) do
    Help.build_help(commando)
  end

  defp missing_switches({result, _args, invalid}, state) do
    missing = state.required |> Enum.filter(fn r ->
      !(Keyword.has_key?(result, r))
    end)
    {result, invalid, missing}
  end

  defp check_help_flag({result, args, invalid}) do
    if Keyword.get(result, :help) == true do
      :help
    else
      {result, args, invalid}
    end
  end

  @spec result_add_defaults(parse_result, State.t) :: parse_result
  defp result_add_defaults(result, commando) do
    defaults = commando.defaults
    defaults |> Enum.reduce(result, fn ({switch, default}, result) ->
      result |> Keyword.put_new(switch, default)
    end)
  end

  @spec add_configurations(State.t, atom(), conf_list) :: State.t
  defp add_configurations(commando, switch, [{:default, default} | tail]) do
    commando
    |> State.add_default(switch, default)
    |> add_configurations(switch, tail)
  end
  defp add_configurations(commando, switch, [{:alias, al} | tail]) do
    commando
    |> State.add_alias(switch, al)
    |> add_configurations(switch, tail)
  end
  defp add_configurations(commando, switch, [{:required, true} | tail]) do
    commando
    |> State.add_required(switch)
    |> add_configurations(switch, tail)
  end
  defp add_configurations(commando, switch, [{:required, _} | tail]) do
    commando |> add_configurations(switch, tail)
  end
  defp add_configurations(commando, _switch, []) do
    commando
  end
end