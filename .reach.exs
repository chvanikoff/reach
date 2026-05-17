[
  layers: [cli: "Mix.Tasks.*", core: "Reach.*"],
  checks: [baseline: ".reach-baseline.json"],
  smells: [
    strict: true,
    fixed_shape_map: [min_occurrences: 20],
    behaviour_candidate: [min_modules: 4]
  ]
]
