[
  layers: [
    cli: ["Mix.Tasks.*", "Reach.CLI.*"],
    plugin: ["Reach.Plugin", "Reach.Plugins.*"],
    evidence: ["Reach.Evidence", "Reach.Evidence.*"],
    smell: ["Reach.Smell.*"],
    check: ["Reach.Check.*"],
    frontend: ["Reach.Frontend", "Reach.Frontend.*", "Reach.Source", "Reach.Source.*"],
    visualize: ["Reach.Visualize", "Reach.Visualize.*"],
    inspect: ["Reach.Inspect.*"],
    project: ["Reach.Project", "Reach.Project.*"],
    config: ["Reach.Config", "Reach.Config.*"],
    core: [
      "Reach",
      "Reach.Analysis",
      "Reach.CallGraph",
      "Reach.Concurrency",
      "Reach.ControlDependence",
      "Reach.ControlFlow",
      "Reach.DataDependence",
      "Reach.DependencySummary",
      "Reach.Dominator",
      "Reach.Effects",
      "Reach.ErlangFrontend",
      "Reach.Graph",
      "Reach.GraphAlgorithms",
      "Reach.HigherOrder",
      "Reach.IR",
      "Reach.IR.*",
      "Reach.Map.*",
      "Reach.OTP",
      "Reach.OTP.*",
      "Reach.SystemDependence",
      "Reach.Trace.*"
    ]
  ],
  deps: [
    forbidden: [
      {:core, :cli},
      {:frontend, :cli},
      {:project, :cli},
      {:visualize, :cli},
      {:evidence, :cli},
      {:smell, :cli},
      {:check, :cli}
    ]
  ],
  calls: [
    forbidden: [
      {"Reach.Evidence.*", ["Reach.CLI.*", "Mix.Task.run/1", "Mix.Task.run/2"]},
      {"Reach.Smell.*", ["Reach.CLI.*", "Mix.Task.run/1", "Mix.Task.run/2"]},
      {"Reach.Check.*", ["Reach.CLI.Render.*", "Mix.Task.run/1", "Mix.Task.run/2"]},
      {"Reach.Frontend.*", ["Reach.CLI.*", "Mix.Task.run/1", "Mix.Task.run/2"]},
      {"Reach.Project*", ["Reach.CLI.Render.*"]},
      {"Reach.Visualize.*", ["Reach.CLI.Commands.*", "Mix.Task.run/1", "Mix.Task.run/2"]},
      {"Reach.Plugin", ["Reach.CLI.*", "Mix.Task.run/1", "Mix.Task.run/2"]},
      {"Reach.Plugins.*", ["Reach.CLI.*", "Mix.Task.run/1", "Mix.Task.run/2"]}
    ]
  ],
  source: [
    forbidden_modules: [
      "Reach.CLI.Analyses.*",
      "Reach.CLI.TaskRunner",
      "Reach.CloneAnalysis.*",
      "Reach.Plugins.JSON"
    ],
    forbidden_files: [
      "lib/reach/cli/analyses/**",
      "lib/reach/cli/task_runner.ex",
      "lib/reach/clone_analysis/**",
      "lib/reach/plugins/json.ex"
    ]
  ],
  checks: [
    baseline: ".reach-baseline.json",
    layer_coverage: [
      require_all_modules: true,
      forbid_multiple_matches: true,
      ignore: [
        "Reach.MixProject",
        "Reach.CLI.JSONEnvelope",
        "Jason.Encoder.*"
      ]
    ]
  ],
  clone_analysis: [
    max_clones: 20
  ],
  smells: [
    strict: true,
    fixed_shape_map: [min_occurrences: 20],
    behaviour_candidate: [min_modules: 4]
  ]
]
