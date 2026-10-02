import Foundation

enum IssueActionResolverError: LocalizedError {
  case stateFieldUnavailable
  case resolvedStateUnavailable
  case resolvedTransitionUnavailable

  var errorDescription: String? {
    switch self {
    case .stateFieldUnavailable:
      "This project does not expose a state field."
    case .resolvedStateUnavailable:
      "This project does not expose a resolved state."
    case .resolvedTransitionUnavailable:
      "This issue cannot transition to a resolved state from its current state."
    }
  }
}

enum IssueActionResolver {
  static func resolveAction(
    issue: IssueDetails,
    schema: ProjectSchema
  ) throws -> IssueAction {
    guard
      let projectField = schema.customFields.first(where: {
        $0.field.fieldType.valueType.lowercased().contains("state")
          || $0.projectFieldType.lowercased().contains("state")
      }),
      let issueField = issue.customFields.first(where: {
        $0.id == projectField.id
          || $0.name.caseInsensitiveCompare(projectField.field.name) == .orderedSame
      })
    else {
      throw IssueActionResolverError.stateFieldUnavailable
    }

    let resolvedValues =
      projectField.bundle?.values.filter {
        $0.archived != true && $0.isResolved == true
      } ?? []

    guard !resolvedValues.isEmpty else {
      throw IssueActionResolverError.resolvedStateUnavailable
    }

    if !issueField.possibleEvents.isEmpty {
      let resolvedNames = Set(
        resolvedValues.flatMap { value in
          [value.displayName, value.localizedName]
            .compactMap { $0?.lowercased() }
        }
      )

      guard
        let event = issueField.possibleEvents.first(where: {
          resolvedNames.contains($0.presentation.lowercased())
        })
      else {
        throw IssueActionResolverError.resolvedTransitionUnavailable
      }

      return .setState(
        issueID: issue.id,
        change: .event(
          fieldID: issueField.id,
          fieldType: issueField.fieldType,
          eventID: event.id
        )
      )
    }

    guard let resolved = resolvedValues.first else {
      throw IssueActionResolverError.resolvedStateUnavailable
    }

    return .setState(
      issueID: issue.id,
      change: .value(
        fieldID: issueField.id,
        fieldType: issueField.fieldType,
        value: .object(["id": .string(resolved.id)])
      )
    )
  }
}
