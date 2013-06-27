reads  last: 2, greater_than: "90%", scale: { on: :consumed, by: 1.7 }
reads  last: 2, greater_than: "80%", scale: { on: :consumed, by: 1.5 }
reads  last: 2, greater_than: "70%", scale: { on: :consumed, by: 1.3 }
reads  last: 2, greater_than: "60%", scale: { on: :consumed, by: 1.1 }

writes last: 2, greater_than: "90%", scale: { on: :consumed, by: 1.7 }
writes last: 2, greater_than: "80%", scale: { on: :consumed, by: 1.5 }
writes last: 2, greater_than: "70%", scale: { on: :consumed, by: 1.3 }
writes last: 2, greater_than: "60%", scale: { on: :consumed, by: 1.1 }

reads  for:  2.hours, less_than: "50%", min: 20, scale: { on: :consumed, by: 1.9 }
writes for:  2.hours, less_than: "50%", min: 20, scale: { on: :consumed, by: 1.9 }
