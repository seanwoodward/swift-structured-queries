import Dependencies
import Foundation
import InlineSnapshotTesting
import StructuredQueries
import StructuredQueriesSQLite
import Testing

extension SnapshotTests {
  @Suite struct CommonTableExpressionTests {
    @Dependency(\.defaultDatabase) var db

    init() throws {
      try db.execute(
        #sql(
          """
          CREATE TABLE "employees" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "bossID" INTEGER REFERENCES "employees",
            "height" INTEGER NOT NULL,
            "name" TEXT NOT NULL
          )
          """
        )
      )
    }

    @Test func countTwoTables() {
      assertQuery(
        With {
          Reminder.select {
            ReminderCount.Columns(count: $0.count())
          }
          RemindersList.select {
            RemindersListCount.Columns(count: $0.count())
          }
        } query: {
          ReminderCount
            .join(RemindersListCount.all) { _, _ in true }
        }
      ) {
        """
        WITH "reminderCounts" AS (
          SELECT count("reminders"."id") AS "count"
          FROM "reminders"
        ), "remindersListCounts" AS (
          SELECT count("remindersLists"."id") AS "count"
          FROM "remindersLists"
        )
        SELECT "reminderCounts"."count", "remindersListCounts"."count"
        FROM "reminderCounts"
        JOIN "remindersListCounts" ON 1
        """
      } results: {
        """
        ┌────┬───┐
        │ 10 │ 3 │
        └────┴───┘
        """
      }

    }

    @Test func basics() {
      assertQuery(
        With {
          Reminder
            .where { !$0.isCompleted }
            .select { IncompleteReminder.Columns(isFlagged: $0.isFlagged, title: $0.title) }
        } query: {
          IncompleteReminder
            .where { $0.title.collate(.nocase).contains("groceries") }
        }
      ) {
        """
        WITH "incompleteReminders" AS (
          SELECT "reminders"."isFlagged" AS "isFlagged", "reminders"."title" AS "title"
          FROM "reminders"
          WHERE NOT ("reminders"."isCompleted")
        )
        SELECT "incompleteReminders"."isFlagged", "incompleteReminders"."title"
        FROM "incompleteReminders"
        WHERE (("incompleteReminders"."title" COLLATE "NOCASE") LIKE '%groceries%')
        """
      } results: {
        """
        ┌──────────────────────┐
        │ IncompleteReminder(  │
        │   isFlagged: false,  │
        │   title: "Groceries" │
        │ )                    │
        └──────────────────────┘
        """
      }
    }

    @Test func insert() {
      assertQuery(
        With {
          Reminder
            .where { !$0.isCompleted }
            .select { IncompleteReminder.Columns(isFlagged: $0.isFlagged, title: $0.title) }
        } query: {
          Reminder.insert {
            ($0.remindersListID, $0.title, $0.isFlagged, $0.isCompleted)
          } select: {
            IncompleteReminder
              .join(Reminder.all) { $0.title.eq($1.title) }
              .select { ($1.remindersListID, $0.title, !$0.isFlagged, true) }
              .limit(1)
          }
          .returning { ($0.id, $0.title) }
        }
      ) {
        """
        WITH "incompleteReminders" AS (
          SELECT "reminders"."isFlagged" AS "isFlagged", "reminders"."title" AS "title"
          FROM "reminders"
          WHERE NOT ("reminders"."isCompleted")
        )
        INSERT INTO "reminders"
        ("remindersListID", "title", "isFlagged", "isCompleted")
        SELECT "reminders"."remindersListID", "incompleteReminders"."title", NOT ("incompleteReminders"."isFlagged"), 1
        FROM "incompleteReminders"
        JOIN "reminders" ON ("incompleteReminders"."title" = "reminders"."title")
        LIMIT 1
        RETURNING "id", "title"
        """
      } results: {
        """
        ┌────┬─────────────┐
        │ 11 │ "Groceries" │
        └────┴─────────────┘
        """
      }
    }

    @Test func update() {
      assertQuery(
        With {
          Reminder
            .where { !$0.isCompleted }
            .select { IncompleteReminder.Columns(isFlagged: $0.isFlagged, title: $0.title) }
        } query: {
          Reminder
            .where { $0.title.in(IncompleteReminder.select(\.title)) }
            .update { $0.title = $0.title.upper() }
            .returning(\.title)
        }
      ) {
        """
        WITH "incompleteReminders" AS (
          SELECT "reminders"."isFlagged" AS "isFlagged", "reminders"."title" AS "title"
          FROM "reminders"
          WHERE NOT ("reminders"."isCompleted")
        )
        UPDATE "reminders"
        SET "title" = upper("reminders"."title")
        WHERE ("reminders"."title" IN (SELECT "incompleteReminders"."title"
        FROM "incompleteReminders"))
        RETURNING "title"
        """
      } results: {
        """
        ┌────────────────────────────┐
        │ "GROCERIES"                │
        │ "HAIRCUT"                  │
        │ "DOCTOR APPOINTMENT"       │
        │ "BUY CONCERT TICKETS"      │
        │ "PICK UP KIDS FROM SCHOOL" │
        │ "TAKE OUT TRASH"           │
        │ "CALL ACCOUNTANT"          │
        └────────────────────────────┘
        """
      }
    }

    @Test func delete() {
      assertQuery(
        With {
          Reminder
            .where { !$0.isCompleted }
            .select { IncompleteReminder.Columns(isFlagged: $0.isFlagged, title: $0.title) }
        } query: {
          Reminder
            .where { $0.title.in(IncompleteReminder.select(\.title)) }
            .delete()
            .returning(\.title)
        }
      ) {
        """
        WITH "incompleteReminders" AS (
          SELECT "reminders"."isFlagged" AS "isFlagged", "reminders"."title" AS "title"
          FROM "reminders"
          WHERE NOT ("reminders"."isCompleted")
        )
        DELETE FROM "reminders"
        WHERE ("reminders"."title" IN (SELECT "incompleteReminders"."title"
        FROM "incompleteReminders"))
        RETURNING "reminders"."title"
        """
      } results: {
        """
        ┌────────────────────────────┐
        │ "Groceries"                │
        │ "Haircut"                  │
        │ "Doctor appointment"       │
        │ "Buy concert tickets"      │
        │ "Pick up kids from school" │
        │ "Take out trash"           │
        │ "Call accountant"          │
        └────────────────────────────┘
        """
      }
    }

    @Test func tableAliasIsCTE() {
      enum TopPriority: AliasName { static var isCommonTableExpression: Bool { true } }
      let cte =
          Reminder
            .where { $0.isHighPriority }
            .select {
              Reminder.as(TopPriority.self).base.Columns(
                id: $0.id,
                assignedUserID: $0.assignedUserID,
                dueDate: $0.dueDate,
                isCompleted: $0.isCompleted,
                isFlagged: $0.isFlagged,
                notes: $0.notes,
                priority: $0.priority,
                remindersListID: $0.remindersListID,
                title: $0.title,
                updatedAt: $0.updatedAt
              )
            }
      assertQuery(
        With {
          unsafeBitCast(cte, to: Select<TableAlias<Reminder, TopPriority>, Reminder, ()>.self)
        } query: {
          Reminder.as(TopPriority.self).all
        }
      ) {
        """
        WITH "topPriorities" AS (
          SELECT "reminders"."id" AS "id", "reminders"."assignedUserID" AS "assignedUserID", "reminders"."dueDate" AS "dueDate", "reminders"."isCompleted" AS "isCompleted", "reminders"."isFlagged" AS "isFlagged", "reminders"."notes" AS "notes", "reminders"."priority" AS "priority", "reminders"."remindersListID" AS "remindersListID", "reminders"."title" AS "title", "reminders"."updatedAt" AS "updatedAt"
          FROM "reminders"
          WHERE ("reminders"."priority" IS 3)
        )
        SELECT "topPriorities"."id", "topPriorities"."assignedUserID", "topPriorities"."dueDate", "topPriorities"."isCompleted", "topPriorities"."isFlagged", "topPriorities"."notes", "topPriorities"."priority", "topPriorities"."remindersListID", "topPriorities"."title", "topPriorities"."updatedAt"
        FROM "topPriorities"
        """
      } results: {
        """
        ┌─────────────────────────────────────────────┐
        │ Reminder(                                   │
        │   id: 3,                                    │
        │   assignedUserID: nil,                      │
        │   dueDate: Date(2001-01-01T00:00:00.000Z),  │
        │   isCompleted: false,                       │
        │   isFlagged: false,                         │
        │   notes: "Ask about diet",                  │
        │   priority: .high,                          │
        │   remindersListID: 1,                       │
        │   title: "Doctor appointment",              │
        │   updatedAt: Date(2040-02-14T23:31:30.000Z) │
        │ )                                           │
        ├─────────────────────────────────────────────┤
        │ Reminder(                                   │
        │   id: 6,                                    │
        │   assignedUserID: nil,                      │
        │   dueDate: Date(2001-01-03T00:00:00.000Z),  │
        │   isCompleted: false,                       │
        │   isFlagged: true,                          │
        │   notes: "",                                │
        │   priority: .high,                          │
        │   remindersListID: 2,                       │
        │   title: "Pick up kids from school",        │
        │   updatedAt: Date(2040-02-14T23:31:30.000Z) │
        │ )                                           │
        ├─────────────────────────────────────────────┤
        │ Reminder(                                   │
        │   id: 8,                                    │
        │   assignedUserID: nil,                      │
        │   dueDate: Date(2001-01-05T00:00:00.000Z),  │
        │   isCompleted: false,                       │
        │   isFlagged: false,                         │
        │   notes: "",                                │
        │   priority: .high,                          │
        │   remindersListID: 2,                       │
        │   title: "Take out trash",                  │
        │   updatedAt: Date(2040-02-14T23:31:30.000Z) │
        │ )                                           │
        └─────────────────────────────────────────────┘
        """
      }
    }
    
    @Test func recursive() {
      assertQuery(
        With {
          Count(value: 1)
            .union(Count.select { Count.Columns(value: $0.value + 1) })
        } query: {
          Count.limit(4)
        }
      ) {
        """
        WITH "counts" AS (
          SELECT 1 AS "value"
            UNION
          SELECT ("counts"."value" + 1) AS "value"
          FROM "counts"
        )
        SELECT "counts"."value"
        FROM "counts"
        LIMIT 4
        """
      } results: {
        """
        ┌───┐
        │ 1 │
        │ 2 │
        │ 3 │
        │ 4 │
        └───┘
        """
      }
    }

    @Test func cte2() {
      assertQuery(
        With {
          Reminder
            .where { !$0.isCompleted }
            .select { IncompleteReminder.Columns(isFlagged: $0.isFlagged, title: $0.title) }
        } query: {
          IncompleteReminder
            .where { $0.title.collate(.nocase).contains("groceries") }
            .select { $0.isFlagged }
        }
      ) {
        """
        WITH "incompleteReminders" AS (
          SELECT "reminders"."isFlagged" AS "isFlagged", "reminders"."title" AS "title"
          FROM "reminders"
          WHERE NOT ("reminders"."isCompleted")
        )
        SELECT "incompleteReminders"."isFlagged"
        FROM "incompleteReminders"
        WHERE (("incompleteReminders"."title" COLLATE "NOCASE") LIKE '%groceries%')
        """
      } results: {
        """
        ┌───────┐
        │ false │
        └───────┘
        """
      }
    }

    @Test func averageHeightOfAliceReportsIncludingAlice() throws {
      let alice = Employee(id: 1, name: "Alice", bossID: nil, height: 120)
      let blob = Employee(id: 2, name: "Blob", bossID: alice.id, height: 90)
      try db.execute(
        Employee.insert {
          alice
          blob
        }
      )
      try db.execute(
        Employee.insert {
          Employee.Draft(name: "Blob Jr", bossID: blob.id, height: 80)
          Employee.Draft(name: "Blob Sr", bossID: blob.id, height: 150)
          Employee.Draft(name: "Blob Esq", bossID: nil, height: 1000)
        }
      )

      let initialCondition = EmployeeReport(id: alice.id, height: alice.height, name: alice.name)
      assertQuery(
        With {
          initialCondition
            .union(
              all: true,
              Employee
                .select { EmployeeReport.Columns(id: $0.id, height: $0.height, name: $0.name) }
                .join(EmployeeReport.all) { $0.bossID.eq($1.id) }
            )
        } query: {
          EmployeeReport
            .select { $0.height.avg() }
        }
      ) {
        """
        WITH "employeeReports" AS (
          SELECT 1 AS "id", 120 AS "height", 'Alice' AS "name"
            UNION ALL
          SELECT "employees"."id" AS "id", "employees"."height" AS "height", "employees"."name" AS "name"
          FROM "employees"
          JOIN "employeeReports" ON ("employees"."bossID" = "employeeReports"."id")
        )
        SELECT avg("employeeReports"."height")
        FROM "employeeReports"
        """
      } results: {
        """
        ┌───────┐
        │ 110.0 │
        └───────┘
        """
      }

      assertQuery(
        #sql(
          """
          WITH \(EmployeeReport.self) AS (
            \(initialCondition)
            UNION ALL
            SELECT \(Employee.id), \(Employee.height), \(Employee.name)
            FROM \(Employee.self) 
            JOIN \(EmployeeReport.self) ON (\(Employee.bossID) = \(EmployeeReport.id))
          ) 
          SELECT \(EmployeeReport.height.avg())
          FROM \(EmployeeReport.self) 
          """,
          as: Double.self
        )
      ) {
        """
        WITH "employeeReports" AS (
          SELECT 1 AS "id", 120 AS "height", 'Alice' AS "name"
          UNION ALL
          SELECT "employees"."id", "employees"."height", "employees"."name"
          FROM "employees" 
          JOIN "employeeReports" ON ("employees"."bossID" = "employeeReports"."id")
        ) 
        SELECT avg("employeeReports"."height")
        FROM "employeeReports" 
        """
      } results: {
        """
        ┌───────┐
        │ 110.0 │
        └───────┘
        """
      }
    }

    @Test func fibonacci() throws {
      assertQuery(
        With {
          Fibonacci(n: 1, prevFib: 0, fib: 1)
            .union(
              Fibonacci
                .select {
                  Fibonacci.Columns(n: $0.n + 1, prevFib: $0.fib, fib: $0.prevFib + $0.fib)
                }
            )
        } query: {
          Fibonacci
            .select(\.fib)
            .limit(10)
        }
      ) {
        """
        WITH "fibonaccis" AS (
          SELECT 1 AS "n", 0 AS "prevFib", 1 AS "fib"
            UNION
          SELECT ("fibonaccis"."n" + 1) AS "n", "fibonaccis"."fib" AS "prevFib", ("fibonaccis"."prevFib" + "fibonaccis"."fib") AS "fib"
          FROM "fibonaccis"
        )
        SELECT "fibonaccis"."fib"
        FROM "fibonaccis"
        LIMIT 10
        """
      } results: {
        """
        ┌────┐
        │ 1  │
        │ 1  │
        │ 2  │
        │ 3  │
        │ 5  │
        │ 8  │
        │ 13 │
        │ 21 │
        │ 34 │
        │ 55 │
        └────┘
        """
      }
    }

    @Test func goldenRatioApproximation() {
      assertQuery(
        With {
          Fibonacci(n: 1, prevFib: 0, fib: 1)
            .union(
              Fibonacci
                .select {
                  Fibonacci.Columns(n: $0.n + 1, prevFib: $0.fib, fib: $0.prevFib + $0.fib)
                }
            )
        } query: {
          Fibonacci
            .select { $0.fib.cast(as: Double.self) / $0.prevFib.cast() }
            .limit(1, offset: 30)
        }
      ) {
        """
        WITH "fibonaccis" AS (
          SELECT 1 AS "n", 0 AS "prevFib", 1 AS "fib"
            UNION
          SELECT ("fibonaccis"."n" + 1) AS "n", "fibonaccis"."fib" AS "prevFib", ("fibonaccis"."prevFib" + "fibonaccis"."fib") AS "fib"
          FROM "fibonaccis"
        )
        SELECT (CAST("fibonaccis"."fib" AS REAL) / CAST("fibonaccis"."prevFib" AS REAL))
        FROM "fibonaccis"
        LIMIT 1 OFFSET 30
        """
      } results: {
        """
        ┌────────────────────┐
        │ 1.6180339887505408 │
        └────────────────────┘
        """
      }
    }
  }
}

@Table @Selection
private struct Fibonacci {
  let n: Int
  let prevFib: Int
  let fib: Int
}

@Table @Selection
private struct IncompleteReminder {
  let isFlagged: Bool
  let title: String
}

@Table @Selection
private struct Count {
  let value: Int
}

extension Count {
  init(queryOutput: Int) {
    value = queryOutput
  }
  var queryOutput: Int {
    value
  }
}

@Table
struct Employee {
  let id: Int
  let name: String
  let bossID: Int?
  var height = 100
}

@Table @Selection
struct EmployeeReport {
  let id: Int
  let height: Int
  let name: String
}

@Table @Selection
struct ReminderCount {
  let count: Int
  var queryOutput: Int {
    count
  }
  init(queryOutput: Int) {
    count = queryOutput
  }
}

@Table @Selection
struct RemindersListCount {
  let count: Int
  var queryOutput: Int {
    count
  }
  init(queryOutput: Int) {
    count = queryOutput
  }
}
