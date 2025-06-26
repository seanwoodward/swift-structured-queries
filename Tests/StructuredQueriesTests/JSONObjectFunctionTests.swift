import Dependencies
import Foundation
import InlineSnapshotTesting
import StructuredQueries
import StructuredQueriesSQLite
import Testing

extension SnapshotTests {
  @MainActor
  @Suite struct JSONObjectFunctionsTests {
    @Dependency(\.defaultDatabase) var db

    @Test func testJsonObject() throws {
      assertQuery(
        Reminder
          .where { $0.id.eq(1) || $0.id.eq(3) }
          .leftJoin(ReminderTag.all) { reminder, lookup in lookup.tagID.eq(3) && reminder.id.eq(lookup.reminderID) }
          .leftJoin(Tag.all) { _, lookup, tag in lookup.tagID.eq(tag.id)}
          .select { reminder, _, tag in
            ReminderWithTagJSON.Columns(
              reminderId: reminder.id,
              title: reminder.title,
              tag: #sql("\(tag.jsonObject())")
            )
          }
      ) {
        """
        SELECT "reminders"."id" AS "reminderId", "reminders"."title" AS "title", CASE WHEN ("tags"."id" IS NOT NULL) THEN json_object('id', json_quote("tags"."id"), 'title', json_quote("tags"."title")) END AS "tag"
        FROM "reminders"
        LEFT JOIN "remindersTags" ON (("remindersTags"."tagID" = 3) AND ("reminders"."id" = "remindersTags"."reminderID"))
        LEFT JOIN "tags" ON ("remindersTags"."tagID" = "tags"."id")
        WHERE (("reminders"."id" = 1) OR ("reminders"."id" = 3))
        """
      }results: {
        """
        ┌────────────────────────────────┐
        │ ReminderWithTagJSON(           │
        │   reminderId: 1,               │
        │   title: "Groceries",          │
        │   tag: Tag(                    │
        │     id: 3,                     │
        │     title: "someday"           │
        │   )                            │
        │ )                              │
        ├────────────────────────────────┤
        │ ReminderWithTagJSON(           │
        │   reminderId: 3,               │
        │   title: "Doctor appointment", │
        │   tag: nil                     │
        │ )                              │
        └────────────────────────────────┘
        """
      }
    }
  }
  
  @Test func testJsonObjectFromValue() throws {
    assertQuery(
      SQLQueryExpression(Values(0, "Groceries", #"{"id": 3, "title": "someday"}"#).query, as: ReminderWithTagJSON.self)
    ) {
      """
      SELECT 0, 'Groceries', '{"id": 3, "title": "someday"}'
      """
    } results: {
      """
      ┌───────────────────────┐
      │ ReminderWithTagJSON(  │
      │   reminderId: 0,      │
      │   title: "Groceries", │
      │   tag: Tag(           │
      │     id: 3,            │
      │     title: "someday"  │
      │   )                   │
      │ )                     │
      └───────────────────────┘
      """
    }
  }

  @Test func testJsonObjectFromValueExplicitNil() throws {
    let query = SQLQueryExpression(Values(0, "Groceries", String?.none).query, as: ReminderWithTagJSON.self)
    assertQuery(
      query
    ) {
      """
      SELECT 0, 'Groceries', NULL
      """
    } results: {
      """
      ┌───────────────────────┐
      │ ReminderWithTagJSON(  │
      │   reminderId: 0,      │
      │   title: "Groceries", │
      │   tag: nil            │
      │ )                     │
      └───────────────────────┘
      """
    }
  }
  
  @Test func justATag() throws {
    assertQuery(
      Tag.limit(1).select {
        JustATag.Columns(
          tag: #sql("\($0.jsonObject())")
        )
      }
    ) {
      """
      SELECT json_object('id', json_quote("tags"."id"), 'title', json_quote("tags"."title")) AS "tag"
      FROM "tags"
      LIMIT 1
      """
    } results: {
      """
      ┌──────────────────┐
      │ JustATag(        │
      │   tag: Tag(      │
      │     id: 1,       │
      │     title: "car" │
      │   )              │
      │ )                │
      └──────────────────┘
      """
    }
  }

  @Test func justATagFromString() throws {
    assertQuery(
      #sql(#"SELECT '{"id": 3, "title": "someday"}' AS "tag""#, as: JustATag.self)
      ) {
      """
      SELECT '{"id": 3, "title": "someday"}' AS "tag"
      """
    } results: {
      """
      ┌──────────────────────┐
      │ JustATag(            │
      │   tag: Tag(          │
      │     id: 3,           │
      │     title: "someday" │
      │   )                  │
      │ )                    │
      └──────────────────────┘
      """
    }
  }
}

@Selection
struct JustATag {
  @Column(as: Tag.JSONRepresentation.self)
  let tag: Tag
}

@Selection @Table("ReminderWithTagJSON")
struct ReminderWithTagJSON {
  let reminderId: Int
  let title: String
  @Column(as: Tag?.JSONRepresentation.self)
  let tag: Tag?
}
