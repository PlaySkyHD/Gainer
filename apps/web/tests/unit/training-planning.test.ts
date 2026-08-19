import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { AccountDatabase } from "../../src/lib/offline/database.ts";
import {
  archiveLocalCustomExercise,
  archiveLocalTemplate,
  createLocalCustomExercise,
  initializeExerciseCatalog,
  readTrainingPlanning,
  saveLocalRotation,
  saveLocalTemplate,
  TrainingPlanningInputError,
  type LocalTemplateItem,
} from "../../src/lib/offline/training-planning.ts";

const databases: AccountDatabase[] = [];

afterEach(async () => {
  const current = databases.splice(0);
  current.forEach((database) => database.close());
  await Promise.all(current.map((database) => Dexie.delete(database.name)));
});

test("versioned base catalog and custom exercise persist without cross-account visibility", async () => {
  const first = await createDatabase();
  const second = await createDatabase();
  await initializeExerciseCatalog(first);
  await initializeExerciseCatalog(second);
  const customId = await createLocalCustomExercise(first, {
    name: "  My Press  ", description: null, targetMuscle: "Chest", muscleGroup: "Chest", equipment: "Cable",
  });

  const firstView = await readTrainingPlanning(first);
  const secondView = await readTrainingPlanning(second);
  assert.equal(firstView.exercises.find((item) => item.id === customId)?.name, "My Press");
  assert.equal(secondView.exercises.some((item) => item.id === customId), false);
  assert.equal(firstView.exercises.filter((item) => !item.isCustom).length, 12);
  assert.equal(await first.outbox.count(), 1);
});

test("template reorder survives reload while invalid input leaves no partial state", async () => {
  const database = await createDatabase();
  const view = await readTrainingPlanning(database);
  const firstExercise = view.exercises[0]?.id as string;
  const secondExercise = view.exercises[1]?.id as string;
  const firstItem = item(firstExercise);
  const secondItem = item(secondExercise);
  const templateId = await saveLocalTemplate(database, { name: "Plan", items: [firstItem, secondItem] });
  await saveLocalTemplate(database, { id: templateId, name: "Plan B", items: [secondItem, firstItem] });

  database.close();
  await database.open();
  const reloaded = await readTrainingPlanning(database);
  const template = reloaded.templates.find((entry) => entry.id === templateId);
  assert.equal(template?.name, "Plan B");
  assert.deepEqual(template?.items.map((entry) => entry.id), [secondItem.id, firstItem.id]);
  const before = await database.outbox.count();
  await assert.rejects(saveLocalTemplate(database, {
    name: "Invalid", items: [{ ...firstItem, plannedSets: 0, minimumRepetitions: 12, maximumRepetitions: 8 }],
  }), TrainingPlanningInputError);
  assert.equal((await readTrainingPlanning(database)).templates.length, 1);
  assert.equal(await database.outbox.count(), before);
});

test("archiving keeps existing references, blocks new selection, and rotation skips archived templates", async () => {
  const database = await createDatabase();
  await readTrainingPlanning(database);
  const customId = await createLocalCustomExercise(database, {
    name: "My Row", description: null, targetMuscle: null, muscleGroup: "Back", equipment: "Cable",
  });
  const firstTemplate = await saveLocalTemplate(database, { name: "First", items: [item(customId)] });
  const baseId = (await readTrainingPlanning(database)).exercises.find((entry) => !entry.isCustom)?.id as string;
  const secondTemplate = await saveLocalTemplate(database, { name: "Second", items: [item(baseId)] });
  await saveLocalRotation(database, [firstTemplate, secondTemplate]);
  await archiveLocalCustomExercise(database, customId);

  const referenced = await readTrainingPlanning(database);
  assert.equal(referenced.exercises.find((entry) => entry.id === customId)?.isArchived, true);
  assert.equal(referenced.templates.find((entry) => entry.id === firstTemplate)?.items[0]?.exerciseId, customId);
  await assert.rejects(saveLocalTemplate(database, { name: "New", items: [item(customId)] }), TrainingPlanningInputError);

  await archiveLocalTemplate(database, firstTemplate);
  const skipped = await readTrainingPlanning(database);
  assert.equal(skipped.nextTemplateId, secondTemplate);
});

function item(exerciseId: string): LocalTemplateItem {
  return {
    id: crypto.randomUUID(), exerciseId, plannedSets: 3,
    minimumRepetitions: 8, maximumRepetitions: 12,
    targetRir: 2, restSeconds: 120, notes: null,
  };
}

async function createDatabase() {
  const database = new AccountDatabase(crypto.randomUUID());
  databases.push(database);
  await database.open();
  return database;
}
