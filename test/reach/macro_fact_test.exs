defmodule Reach.MacroFactTest do
  use ExUnit.Case, async: true

  alias Reach.MacroFact

  test "collects module-level DSL declarations and nested declaration blocks" do
    source = ~S'''
    defmodule MyAppWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/", MyAppWeb do
        pipe_through :browser
        get "/health", HealthController, :show
      end
    end
    '''

    assert {:ok, facts} = MacroFact.collect_source(source, file: "router.ex")

    assert Enum.map(facts, & &1.name) == [:use, :pipeline, :plug, :scope, :pipe_through, :get]

    assert %MacroFact{
             owner_module: MyAppWeb.Router,
             target: Phoenix.Router,
             call_module: Phoenix.Router,
             source: %{file: "router.ex", line: 2},
             generated?: false
           } = Enum.at(facts, 0)

    assert %MacroFact{name: :plug, nesting: [:pipeline]} = Enum.at(facts, 2)

    assert %MacroFact{name: :get, arity: 3, nesting: [:scope], target: {nil, :get, 3}} =
             Enum.at(facts, 5)
  end

  test "collects Ash-style declarations without descending into function bodies" do
    source = ~S'''
    defmodule MyApp.Blog.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
        attribute :title, :string
      end

      actions do
        defaults [:read]

        create :publish do
          accept [:title]
        end
      end

      def helper do
        ordinary_call()
      end
    end
    '''

    assert {:ok, facts} = MacroFact.collect_source(source)

    names = Enum.map(facts, & &1.name)

    assert names == [
             :use,
             :attributes,
             :uuid_primary_key,
             :attribute,
             :actions,
             :defaults,
             :create,
             :accept
           ]

    refute :ordinary_call in names
    assert %MacroFact{name: :accept, nesting: [:actions, :create]} = List.last(facts)
  end

  test "keeps dynamic module names as nil instead of crashing" do
    source = ~S'''
    defmodule MyApp.Dynamic do
      use module
    end
    '''

    assert {:ok, [%MacroFact{name: :use, call_module: nil, target: nil}]} =
             MacroFact.collect_source(source)
  end
end
