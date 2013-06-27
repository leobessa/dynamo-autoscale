reads  last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }
writes last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }

reads  for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }
writes for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }
