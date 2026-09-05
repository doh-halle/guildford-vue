ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(GuildfordVue.Repo, :manual)

# Sprint 1c slice A — defect 002 bypass. The recorder queries `:cover`
# directly post-suite and writes `cover/guildford_vue_coverage.json` —
# our canonical coverage truth that does NOT silently drop the
# exam_centres subsystem like ExCoveralls does.
GuildfordVue.Test.CoverRecorder.install()
