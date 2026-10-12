const demo = db.getSiblingDB("infrastructure_demo");
demo.customers.bulkWrite([
  {
    updateOne: {
      filter: { _id: "demo-alice" },
      update: { $set: { name: "Alice Demo", email: "alice@example.test" } },
      upsert: true
    }
  },
  {
    updateOne: {
      filter: { _id: "demo-bob" },
      update: { $set: { name: "Bob Demo", email: "bob@example.test" } },
      upsert: true
    }
  }
]);
