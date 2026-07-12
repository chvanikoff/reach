defmodule Reach.OTP.SuppressionsTest do
  use ExUnit.Case, async: true

  alias Reach.OTP.Analysis
  alias Reach.Project

  test "control: discarded replies and ets coupling are reported without comments" do
    project =
      project_for(~S'''
      defmodule OtpFixture.Control do
        def kick(pid, value) do
          GenServer.call(pid, :refresh)
          :ets.insert(:reach_fixture_table, {:latest, value})
          :ok
        end
      end
      ''')

    result = Analysis.run(project, nil)

    assert result.dead_replies != []
    assert result.hidden_coupling.ets != %{}
  end

  test "disable-next-line dead_reply suppresses a dead reply finding" do
    project =
      project_for(~S'''
      defmodule OtpFixture.Suppressed do
        def kick(pid) do
          # reach:disable-next-line dead_reply
          GenServer.call(pid, :refresh)
          :ok
        end
      end
      ''')

    result = Analysis.run(project, nil)

    assert result.dead_replies == []
  end

  test "otp group token suppresses hidden coupling entries" do
    project =
      project_for(~S'''
      defmodule OtpFixture.Ets do
        def track(value) do
          # reach:disable-next-line otp
          :ets.insert(:reach_fixture_table, {:latest, value})
          value
        end
      end
      ''')

    result = Analysis.run(project, nil)

    assert result.hidden_coupling.ets == %{}
  end

  defp project_for(source) do
    dir = Path.join(System.tmp_dir!(), "reach-otp-suppressions-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)
    Project.from_sources([path])
  end
end
