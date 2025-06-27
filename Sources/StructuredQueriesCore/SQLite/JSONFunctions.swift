import Foundation
import StructuredQueriesSupport

extension QueryExpression {
  /// Wraps this expression with the `json_array_length` function.
  ///
  /// ```swift
  /// Reminder.select { $0.tags.jsonArrayLength() }
  /// // SELECT json_array_length("reminders"."tags") FROM "reminders"
  /// ```
  ///
  /// - Returns: An integer expression of the `json_array_length` function wrapping this expression.
  public func jsonArrayLength<Element: Codable & Sendable>() -> some QueryExpression<Int>
  where QueryValue == [Element].JSONRepresentation {
    QueryFunction("json_array_length", self)
  }
}

extension QueryExpression where QueryValue: Codable & QueryBindable & Sendable {
  /// A JSON array aggregate of this expression
  ///
  /// Concatenates all of the values in a group.
  ///
  /// ```swift
  /// Reminder.select { $0.title.jsonGroupArray() }
  /// // SELECT json_group_array("reminders"."title") FROM "reminders"
  /// ```
  ///
  /// - Parameters:
  ///   - isDistinct: An boolean to enable the `DISTINCT` clause to apply to the aggregation.
  ///   - order: An `ORDER BY` clause to apply to the aggregation.
  ///   - filter: A `FILTER` clause to apply to the aggregation.
  /// - Returns: A JSON array aggregate of this expression.
  public func jsonGroupArray(
    isDistinct: Bool = false,
    order: (some QueryExpression)? = Bool?.none,
    filter: (some QueryExpression<Bool>)? = Bool?.none
  ) -> some QueryExpression<[QueryValue].JSONRepresentation> {
    AggregateFunction(
      "json_group_array",
      isDistinct: isDistinct,
      [queryFragment],
      order: order?.queryFragment,
      filter: filter?.queryFragment
    )
  }
}

extension PrimaryKeyedTableDefinition where QueryValue: Codable & Sendable {
  /// A JSON array representation of the aggregation of a table's columns.
  ///
  /// Constructs a JSON array of JSON objects with a field for each column of the table. This can be
  /// useful for loading many associated values in a single query. For example, to query for every
  /// reminders list, along with the array of reminders it is associated with, one can define a
  /// custom `@Selection` for that data and query as follows:
  ///
  /// @Row {
  ///   @Column {
  ///     ```swift
  ///     @Selection struct Row {
  ///       let remindersList: RemindersList
  ///       @Column(as: [Reminder].JSONRepresentation.self)
  ///       let reminders: [Reminder]
  ///     }
  ///     RemindersList
  ///       .join(Reminder.all) { $0.id.eq($1.remindersListID) }
  ///       .select {
  ///         Row.Columns(
  ///           remindersList: $0,
  ///           reminders: $1.jsonGroupArray()
  ///         )
  ///       }
  ///     ```
  ///   }
  ///   @Column {
  ///     ```sql
  ///      SELECT
  ///       "remindersLists".…,
  ///       CASE WHEN
  ///         ("reminders"."id" IS NOT NULL)
  ///       THEN
  ///         json_object(
  ///           'id', json_quote("id"),
  ///           'title', json_quote("title"),
  ///           'priority', json_quote("priority")
  ///         )
  ///       END AS "reminders"
  ///     FROM "remindersLists"
  ///     JOIN "reminders"
  ///       ON ("remindersLists"."id" = "reminders"."remindersListID")
  ///     ```
  ///   }
  /// }
  ///
  /// - Parameters:
  ///   - isDistinct: An boolean to enable the `DISTINCT` clause to apply to the aggregation.
  ///   - order: An `ORDER BY` clause to apply to the aggregation.
  ///   - filter: A `FILTER` clause to apply to the aggregation.
  /// - Returns: A JSON array aggregate of this table.
  public func jsonGroupArray(
    isDistinct: Bool = false,
    order: (some QueryExpression)? = Bool?.none,
    filter: (some QueryExpression<Bool>)? = Bool?.none
  ) -> some QueryExpression<[QueryValue].JSONRepresentation> {
    AggregateFunction(
      "json_group_array",
      isDistinct: isDistinct,
      [jsonObject().queryFragment],
      order: order?.queryFragment,
      filter: filter?.queryFragment
    )
  }
}

extension PrimaryKeyedTableDefinition where QueryValue: _OptionalProtocol & Sendable & Codable, QueryValue.Wrapped: Codable & Sendable {
  /// A JSON Object representing the table's properties.
  ///
  /// @Row {
  ///   @Column {
  ///       ```swift
  ///       @Selection struct Row {
  ///         let reminderID: Int
  ///         @Column(as: Tag?.JSONRepresentation.self)
  ///         let tag: Tag?
  ///       }
  ///       Reminder
  ///         .leftJoin(ReminderTag.all) { $0.id.eq($1.reminderID) }
  ///         .leftJoin(Tag.all) { $1.tagID.eq($2.id) && $2.id == 3 }
  ///         .select {
  ///           Row.Columns(
  ///             reminderID: $0.id,
  ///             tag: $2.jsonObject()
  ///           )
  ///         }
  ///         ```
  ///   }
  ///   @Column {
  ///     ```sql
  ///     SELECT "reminders".id" AS "remindersID",
  ///     CASE WHEN ("tags"."id" IS NOT NULL)
  ///     THEN json_object('id', "tags"."id", 'title', "tags"."title")
  ///     END AS "tag"
  ///     FROM "reminders"
  ///     LEFT JOIN "remindersTags" ON ("reminders"."id" = "remindersTags"."reminderID"))
  ///       AND (("remindersTags"."tagID" = 3)
  ///     LEFT JOIN "tags" ON ("remindersTags"."tagID" = "tags"."id")
  ///     ```
  ///   }
  /// }
  public func jsonObject() -> some QueryExpression<_CodableJSONRepresentation<QueryValue.Wrapped>> {
    SQLQueryExpression("CASE WHEN \(primaryKey.isNot(nil)) THEN json_object(\(jsonColumns)) END")
  }

  /// A JSON array representation of the aggregation of a table's columns.
  ///
  /// Constructs a JSON array of JSON objects with a field for each column of the table. This can be
  /// useful for loading many associated values in a single query. For example, to query for every
  /// reminders list, along with the array of reminders it is associated with, one can define a
  /// custom `@Selection` for that data and query as follows:
  ///
  /// @Row {
  ///   @Column {
  ///     ```swift
  ///     @Selection struct Row {
  ///       let remindersList: RemindersList
  ///       @Column(as: [Reminder].JSONRepresentation.self)
  ///       let reminders: [Reminder]
  ///     }
  ///     RemindersList
  ///       .leftJoin(Reminder.all) { $0.id.eq($1.remindersListID) }
  ///       .select {
  ///         Row.Columns(
  ///           remindersList: $0,
  ///           reminders: $1.jsonGroupArray()
  ///         )
  ///       }
  ///     ```
  ///   }
  ///   @Column {
  ///     ```sql
  ///      SELECT
  ///       "remindersLists".…,
  ///       CASE WHEN
  ///         ("reminders"."id" IS NOT NULL)
  ///       THEN
  ///         json_object(
  ///           'id', json_quote("id"),
  ///           'title', json_quote("title"),
  ///           'priority', json_quote("priority")
  ///         )
  ///       END AS "reminders"
  ///     FROM "remindersLists"
  ///     JOIN "reminders"
  ///       ON ("remindersLists"."id" = "reminders"."remindersListID")
  ///     ```
  ///   }
  /// }
  ///
  /// - Parameters:
  ///   - isDistinct: An boolean to enable the `DISTINCT` clause to apply to the aggregation.
  ///   - order: An `ORDER BY` clause to apply to the aggregation.
  ///   - filter: A `FILTER` clause to apply to the aggregation.
  /// - Returns: A JSON array aggregate of this table.
  public func jsonGroupArray(
    isDistinct: Bool = false,
    order: (some QueryExpression)? = Bool?.none,
    filter: (some QueryExpression<Bool>)? = Bool?.none
  ) -> some QueryExpression<[QueryValue.Wrapped].JSONRepresentation> {
    let filterQueryFragment =
      if let filter {
        self.primaryKey.isNot(nil).and(filter).queryFragment
      } else {
        self.primaryKey.isNot(nil).queryFragment
      }
    return AggregateFunction(
      "json_group_array",
      isDistinct: isDistinct,
      [jsonObject().queryFragment],
      order: order?.queryFragment,
      filter: filterQueryFragment
    )
  }
}

extension TableDefinition where QueryValue: Sendable & Codable {
  /// A JSON Object representing the table's properties.
  ///
  /// @Row {
  ///   @Column {
  ///       ```swift
  ///       @Selection struct Row {
  ///         let reminderID: Int
  ///         @Column(as: Tag?.JSONRepresentation.self)
  ///         let tag: Tag?
  ///       }
  ///       Reminder
  ///         .leftJoin(ReminderTag.all) { $0.id.eq($1.reminderID) }
  ///         .leftJoin(Tag.all) { $1.tagID.eq($2.id) && $2.id == 3 }
  ///         .select {
  ///           Row.Columns(
  ///             reminderID: $0.id,
  ///             tag: $2.jsonObject()
  ///           )
  ///         }
  ///         ```
  ///   }
  ///   @Column {
  ///     ```sql
  ///     SELECT "reminders".id" AS "remindersID",
  ///     CASE WHEN ("tags"."id" IS NOT NULL)
  ///     THEN json_object('id', "tags"."id", 'title', "tags"."title")
  ///     END AS "tag"
  ///     FROM "reminders"
  ///     LEFT JOIN "remindersTags" ON ("reminders"."id" = "remindersTags"."reminderID"))
  ///       AND (("remindersTags"."tagID" = 3)
  ///     LEFT JOIN "tags" ON ("remindersTags"."tagID" = "tags"."id")
  ///     ```
  ///   }
  /// }
  public func jsonObject() -> some QueryExpression<_CodableJSONRepresentation<QueryValue>> {
    SQLQueryExpression("json_object(\(jsonColumns))")
  }
  
  fileprivate var jsonColumns: some QueryExpression<QueryValue> {
    func open<TableColumn: TableColumnExpression>(_ column: TableColumn) -> QueryFragment {
      typealias Value = TableColumn.QueryValue._Optionalized.Wrapped
      
      func isJSONRepresentation<T: Codable & Sendable>(_: T.Type, isOptional: Bool = false) -> Bool
      {
        func isOptionalJSONRepresentation<U: _OptionalProtocol>(_: U.Type) -> Bool {
          if let codableType = U.Wrapped.self as? any (Codable & Sendable).Type {
            return isJSONRepresentation(codableType, isOptional: true)
          } else {
            return false
          }
        }
        if let optionalType = T.self as? any _OptionalProtocol.Type {
          return isOptionalJSONRepresentation(optionalType)
        } else if isOptional {
          return TableColumn.QueryValue.self == T.JSONRepresentation?.self
        } else {
          return Value.self == T.JSONRepresentation.self
        }
      }
      
      if Value.self == Bool.self {
        return """
          \(quote: column.name, delimiter: .text), \
          json(CASE \(column) WHEN 0 THEN 'false' WHEN 1 THEN 'true' END)
          """
      } else if Value.self == Date.UnixTimeRepresentation.self {
        return "\(quote: column.name, delimiter: .text), datetime(\(column), 'unixepoch')"
      } else if Value.self == Date.JulianDayRepresentation.self {
        return "\(quote: column.name, delimiter: .text), datetime(\(column), 'julianday')"
      } else if let codableType = TableColumn.QueryValue.QueryOutput.self
        as? any (Codable & Sendable).Type,
        isJSONRepresentation(codableType)
      {
        return "\(quote: column.name, delimiter: .text), json(\(column))"
      } else {
        return "\(quote: column.name, delimiter: .text), json_quote(\(column))"
      }
    }
    let fragment: QueryFragment = Self.allColumns
      .map { open($0) }
      .joined(separator: ", ")
    return SQLQueryExpression("\(fragment)")
  }
}
