reads  last: 2, greater_than: "90%", scale: { on: :consumed, by: 1.7 }
reads  last: 2, greater_than: "80%", scale: { on: :consumed, by: 1.5 }

writes last: 2, greater_than: "90%", scale: { on: :consumed, by: 1.7 }
writes last: 2, greater_than: "80%", scale: { on: :consumed, by: 1.5 }

reads  for:  2.hours, less_than: "20%", min: 10, scale: { on: :consumed, by: 1.8 }
reads  for:  2.hours, less_than: "30%", min: 10, scale: { on: :consumed, by: 1.8 }

writes for:  2.hours, less_than: "20%", min: 10, scale: { on: :consumed, by: 1.8 }
writes for:  2.hours, less_than: "30%", min: 10, scale: { on: :consumed, by: 1.8 }
