import Dependencies
import Foundation
import InlineSnapshotTesting
import StructuredQueries
import StructuredQueriesSQLite
import Testing

extension SnapshotTests {
  @MainActor
  @Suite struct JSONFunctionsTests {
    @Dependency(\.defaultDatabase) var db

    @Test func jsonGroupArray() {
      assertQuery(
        Reminder.select {
          $0.title.jsonGroupArray()
        }
      ) {
        """
        SELECT json_group_array(reminders.title)
        FROM reminders
        """
      }results: {
        """
        ┌────────────────────────────────────┐
        │ [                                  │
        │   [0]: "Groceries",                │
        │   [1]: "Haircut",                  │
        │   [2]: "Doctor appointment",       │
        │   [3]: "Take a walk",              │
        │   [4]: "Buy concert tickets",      │
        │   [5]: "Pick up kids from school", │
        │   [6]: "Get laundry",              │
        │   [7]: "Take out trash",           │
        │   [8]: "Call accountant",          │
        │   [9]: "Send weekly emails"        │
        │ ]                                  │
        └────────────────────────────────────┘
        """
      }
    }

    @Test func jsonGroupArrayDisctinct() {
      assertQuery(
        Reminder.select {
          $0.priority.jsonGroupArray(isDistinct: true)
        }
      ) {
        """
        SELECT json_group_array(DISTINCT reminders.priority)
        FROM reminders
        """
      }results: {
        """
        ┌────────────────┐
        │ [              │
        │   [0]: nil,    │
        │   [1]: .high,  │
        │   [2]: .low,   │
        │   [3]: .medium │
        │ ]              │
        └────────────────┘
        """
      }
    }

    @Test func jsonArrayLength() {
      assertQuery(
        Reminder.select {
          $0.title.jsonGroupArray().jsonArrayLength()
        }
      ) {
        """
        SELECT json_array_length(json_group_array(reminders.title))
        FROM reminders
        """
      }results: {
        """
        ┌────┐
        │ 10 │
        └────┘
        """
      }
    }

    @Test func queryJSON() throws {
      try db.execute(Reminder.delete())
      try db.execute(
        Reminder.insert {
          Reminder.Draft(
            notes: #"""
              [{"body": "* Milk\n* Eggs"},{"body": "* Eggs"},]
              """#,
            remindersListID: 1,
            title: "Get groceries"
          )
          Reminder.Draft(
            notes: "[]",
            remindersListID: 1,
            title: "Call accountant"
          )
        }
      )

      assertQuery(
        Reminder
          .select {
            (
              $0.title,
              #sql("\($0.notes) ->> '$[#-1].body'", as: String?.self)
            )
          }
      ) {
        """
        SELECT reminders.title, reminders.notes ->> '$[#-1].body'
        FROM reminders
        """
      }results: {
        """
        ┌───────────────────┬──────────┐
        │ "Get groceries"   │ "* Eggs" │
        │ "Call accountant" │ nil      │
        └───────────────────┴──────────┘
        """
      }
    }

    @Test func jsonAssociation_Reminder() {
      assertQuery(
        Reminder
          .group(by: \.id)
          .leftJoin(ReminderTag.all) { $0.id.eq($1.reminderID) }
          .leftJoin(Tag.all) { $1.tagID.eq($2.id) }
          .leftJoin(User.all) { $0.assignedUserID.eq($3.id) }
          .select { reminder, _, tag, user in
            ReminderRow.Columns(
              assignedUser: user,
              reminder: reminder,
              tags: tag.jsonGroupArray()
            )
          }
          .limit(2)
      ) {
        """
        SELECT users.id, users.name AS assignedUser, reminders.id, reminders.assignedUserID, reminders.dueDate, reminders.isCompleted, reminders.isFlagged, reminders.notes, reminders.priority, reminders.remindersListID, reminders.title, reminders.updatedAt AS reminder, json_group_array(CASE WHEN (tags.id IS NOT NULL) THEN json_object(id, json_quote(tags.id), title, json_quote(tags.title)) END) FILTER (WHERE tags.id IS NOT NULL) AS tags
        FROM reminders
        LEFT JOIN remindersTags ON (reminders.id = remindersTags.reminderID)
        LEFT JOIN tags ON (remindersTags.tagID = tags.id)
        LEFT JOIN users ON (reminders.assignedUserID = users.id)
        GROUP BY reminders.id
        LIMIT 2
        """
      }results: {
        """
        ambiguous column name: id
        """
      }
    }

    @Test func jsonAssociation_RemindersList() throws {
      assertQuery(
        RemindersList
          .group(by: \.id)
          .leftJoin(Milestone.all) { $0.id.eq($1.remindersListID) }
          .leftJoin(Reminder.incomplete) { $0.id.eq($2.remindersListID) }
          .select {
            RemindersListRow.Columns(
              remindersList: $0,
              milestones: $1.jsonGroupArray(isDistinct: true),
              reminders: $2.jsonGroupArray(isDistinct: true)
            )
          }
          .limit(1)
      ) {
        """
        SELECT remindersLists.id, remindersLists.color, remindersLists.title, remindersLists.position AS remindersList, json_group_array(DISTINCT CASE WHEN (milestones.id IS NOT NULL) THEN json_object(id, json_quote(milestones.id), remindersListID, json_quote(milestones.remindersListID), title, json_quote(milestones.title)) END) FILTER (WHERE milestones.id IS NOT NULL) AS milestones, json_group_array(DISTINCT CASE WHEN (reminders.id IS NOT NULL) THEN json_object(id, json_quote(reminders.id), assignedUserID, json_quote(reminders.assignedUserID), dueDate, json_quote(reminders.dueDate), isCompleted, json(CASE reminders.isCompleted WHEN 0 THEN 'false' WHEN 1 THEN 'true' END), isFlagged, json(CASE reminders.isFlagged WHEN 0 THEN 'false' WHEN 1 THEN 'true' END), notes, json_quote(reminders.notes), priority, json_quote(reminders.priority), remindersListID, json_quote(reminders.remindersListID), title, json_quote(reminders.title), updatedAt, json_quote(reminders.updatedAt)) END) FILTER (WHERE reminders.id IS NOT NULL) AS reminders
        FROM remindersLists
        LEFT JOIN milestones ON (remindersLists.id = milestones.remindersListID)
        LEFT JOIN reminders ON (remindersLists.id = reminders.remindersListID)
        WHERE NOT (reminders.isCompleted)
        GROUP BY remindersLists.id
        LIMIT 1
        """
      }results: {
        """
        ambiguous column name: id
        """
      }
    }

    // This test is showing a missing feature
    @Test func jsonGroupArrayMultiplePrimaryKeys() {
      assertQuery(
        Reminder
          .join(ReminderTag.all) { $0.id.eq($1.reminderID) }
          .select {
            ReminderTagList.Columns(
              reminder: $0,
              tags: $1.jsonGroupArray()
            )
          }
      ) {
        """
        SELECT reminders.id, reminders.assignedUserID, reminders.dueDate, reminders.isCompleted, reminders.isFlagged, reminders.notes, reminders.priority, reminders.remindersListID, reminders.title, reminders.updatedAt AS reminder, json_group_array(CASE WHEN (remindersTags.id IS NOT NULL) THEN json_object(id, json_quote(remindersTags.id), reminderID, json_quote(remindersTags.reminderID), tagID, json_quote(remindersTags.tagID)) END) AS tags
        FROM reminders
        JOIN remindersTags ON (reminders.id = remindersTags.reminderID)
        """
      }results: {
        """
        ambiguous column name: id
        """
      }
    }

    @Test func seyden() throws {
        try db.execute(
            """
            CREATE TABLE "seydens" (
              "sourceId" TEXT NOT NULL,
              "titleId" TEXT NOT NULL,
              "description" TEXT NOT NULL,
              PRIMARY KEY("sourceId", "titleId")
            )
            """
        )

        try db.execute(
            Seyden.insert {
                Seyden.Draft(sourceId: "Asura", titleId: "Genshin", description: "Blob")
                Seyden.Draft(sourceId: "Asura", titleId: "Swordmaster", description: "Blob")
            }
        )

        assertQuery(Seyden.all) {
          """
          SELECT seydens.sourceId, seydens.titleId, seydens.description
          FROM seydens
          """
        }results: {
          """
          ┌───────────────────────────┐
          │ Seyden(                   │
          │   sourceId: "Asura",      │
          │   titleId: "Genshin",     │
          │   description: "Blob"     │
          │ )                         │
          ├───────────────────────────┤
          │ Seyden(                   │
          │   sourceId: "Asura",      │
          │   titleId: "Swordmaster", │
          │   description: "Blob"     │
          │ )                         │
          └───────────────────────────┘
          """
        }

        assertQuery(Seyden.where { $0.sourceId.eq("Asura") && $0.titleId.eq("Genshin") }) {
          """
          SELECT seydens.sourceId, seydens.titleId, seydens.description
          FROM seydens
          WHERE ((seydens.sourceId = Asura) AND (seydens.titleId = Genshin))
          """
        }results: {
          """
          ┌───────────────────────┐
          │ Seyden(               │
          │   sourceId: "Asura",  │
          │   titleId: "Genshin", │
          │   description: "Blob" │
          │ )                     │
          └───────────────────────┘
          """
        }
    }

    @Test func foo() throws {
      try db.execute(
        Token.insert {
          Token.Draft(name: "A", axis: "x", value: 42, description: "Blob")
          Token.Draft(name: "B", axis: "y", value: 42, description: "Blob")
        }
      )

      assertQuery(Token.insert {
          Token.Draft(name: "A", axis: "x", value: 42, description: "Blob")
          Token.Draft(name: "B", axis: "y", value: 42, description: "Blob")
      }.returning(\.self)) {
        """
        INSERT INTO "tokens"
        ("name", "axis", "value", "description")
        VALUES
        ('A', 'x', 42, 'Blob'), ('B', 'y', 42, 'Blob')
        RETURNING "name", "axis", "value", "description"
        """
      }results: {
        """
        UNIQUE constraint failed: tokens.name, tokens.axis
        """
      }

      assertQuery(Token.all) {
        """
        SELECT "tokens"."name", "tokens"."axis", "tokens"."value", "tokens"."description"
        FROM "tokens"
        """
      }results: {
        """
        ┌───────────────────────┐
        │ Token(                │
        │   name: "A",          │
        │   axis: "x",          │
        │   value: 42,          │
        │   description: "Blob" │
        │ )                     │
        ├───────────────────────┤
        │ Token(                │
        │   name: "B",          │
        │   axis: "y",          │
        │   value: 42,          │
        │   description: "Blob" │
        │ )                     │
        └───────────────────────┘
        """
      }

      assertQuery(
        Token.where {
            $0.axis.eq("x")
        }
      ) {
        """
        SELECT "tokens"."name", "tokens"."axis", "tokens"."value", "tokens"."description"
        FROM "tokens"
        WHERE ("tokens"."axis" = 'x')
        """
      }results: {
        """
        ┌───────────────────────┐
        │ Token(                │
        │   name: "A",          │
        │   axis: "x",          │
        │   value: 42,          │
        │   description: "Blob" │
        │ )                     │
        └───────────────────────┘
        """
      }
    }

  }
}

@Selection
private struct ReminderRow: Codable {
  let assignedUser: User?
  let reminder: Reminder
  @Column(as: [Tag].JSONRepresentation.self)
  let tags: [Tag]
}

@Selection
private struct RemindersListRow {
  let remindersList: RemindersList
  @Column(as: [Milestone].JSONRepresentation.self)
  let milestones: [Milestone]
  @Column(as: [Reminder].JSONRepresentation.self)
  let reminders: [Reminder]
}

@Selection
struct ReminderTagList {
  let reminder: Reminder
  @Column(as: [ReminderTag].JSONRepresentation.self)
  let tags: [ReminderTag]
}

@Table
struct Token {
  @Column("name", primaryKey: true)
  let name: String
  @Column("axis", primaryKey: true)
  let axis: String
  var value = 0
  var description = ""
}

@Table
struct Seyden: Codable, Equatable {
    @Column("sourceId", primaryKey: true)
    let sourceId: String

    @Column("titleId", primaryKey: true)
    let titleId: String

    var description = ""
}
