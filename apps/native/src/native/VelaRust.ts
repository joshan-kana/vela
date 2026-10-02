import { NativeModules } from 'react-native';

export type ConnectedUser = {
  id: string;
  login: string;
  full_name: string;
  email: string | null;
  guest: boolean;
};

export type MyWorkIssue = {
  id: string;
  id_readable: string;
  summary: string;
  resolved_at: number | null;
};

export type MyWork = {
  user: ConnectedUser;
  issues: MyWorkIssue[];
};

export type CapabilityState = 'available' | 'forbidden' | 'unsupported';

export type Discovered<T> = {
  capability: CapabilityState;
  items: T[];
};

export type ProjectRef = {
  id: string;
  short_name: string;
  name: string;
  archived: boolean | null;
};

export type UserRef = {
  id: string;
  login: string;
  full_name: string;
};

export type AgileBoard = {
  id: string;
  name: string;
  owner: UserRef | null;
};

export type SavedQuery = {
  id: string;
  name: string;
  query: string | null;
  owner: UserRef | null;
};

export type IssueLinkType = {
  id: string;
  name: string;
  source_to_target: string;
  target_to_source: string | null;
  directed: boolean;
  aggregation: boolean;
  read_only: boolean;
};

export type YouTrackDiscovery = {
  projects: Discovered<ProjectRef>;
  users: CapabilityState;
  issue_link_types: Discovered<IssueLinkType>;
  agile_boards: CapabilityState;
  saved_queries: CapabilityState;
};

export type FieldType = {
  id: string;
  value_type: string;
  is_multi_value: boolean;
};

export type BundleValue = {
  id: string;
  value_type: string;
  display_name: string;
  localized_name: string | null;
  archived: boolean | null;
  ordinal: number | null;
  is_resolved: boolean | null;
};

export type FieldBundle = {
  id: string;
  bundle_type: string;
  values: BundleValue[];
};

export type CustomFieldDefinition = {
  id: string;
  name: string;
  localized_name: string | null;
  aliases: string | null;
  field_type: FieldType;
};

export type ProjectCustomField = {
  id: string;
  project_field_type: string;
  field: CustomFieldDefinition;
  can_be_empty: boolean;
  is_public: boolean;
  ordinal: number;
  bundle: FieldBundle | null;
};

export type ProjectSchema = {
  project: ProjectRef;
  custom_fields: ProjectCustomField[];
};

export type FieldEvent = {
  id: string;
  presentation: string;
};

export type CustomFieldValue = {
  id: string;
  name: string;
  field_type: string;
  value: unknown;
  possible_events: FieldEvent[];
};

export type IssueDetails = {
  id: string;
  id_readable: string;
  summary: string;
  description: string | null;
  created_at: number;
  updated_at: number;
  resolved_at: number | null;
  project: ProjectRef;
  custom_fields: CustomFieldValue[];
};

export type IssueRef = {
  id: string;
  id_readable: string;
  summary: string;
  resolved_at: number | null;
};

export type IssueLink = {
  id: string;
  direction: string;
  link_type: IssueLinkType;
  issues: IssueRef[];
};

type BridgeResponse<T> =
  | {
      status: 'ok';
      data: T;
    }
  | {
      status: 'error';
      message: string;
    };

type VelaRustModule = {
  discover?(
    serviceUrl: string,
    bearerToken: string,
  ): Promise<YouTrackDiscovery>;
  discoverJson?(serviceUrl: string, bearerToken: string): Promise<string>;
  loadProjectSchema?(
    serviceUrl: string,
    bearerToken: string,
    projectId: string,
  ): Promise<ProjectSchema>;
  loadProjectSchemaJson?(
    serviceUrl: string,
    bearerToken: string,
    projectId: string,
  ): Promise<string>;
  loadUsers?(
    serviceUrl: string,
    bearerToken: string,
    skip: number,
    top: number,
  ): Promise<UserRef[]>;
  loadUsersJson?(
    serviceUrl: string,
    bearerToken: string,
    skip: number,
    top: number,
  ): Promise<string>;
  loadAgileBoards?(
    serviceUrl: string,
    bearerToken: string,
    skip: number,
    top: number,
  ): Promise<AgileBoard[]>;
  loadAgileBoardsJson?(
    serviceUrl: string,
    bearerToken: string,
    skip: number,
    top: number,
  ): Promise<string>;
  loadSavedQueries?(
    serviceUrl: string,
    bearerToken: string,
    skip: number,
    top: number,
  ): Promise<SavedQuery[]>;
  loadSavedQueriesJson?(
    serviceUrl: string,
    bearerToken: string,
    skip: number,
    top: number,
  ): Promise<string>;
  loadIssueDetails?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
  ): Promise<IssueDetails>;
  loadIssueDetailsJson?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
  ): Promise<string>;
  loadIssueLinks?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
  ): Promise<IssueLink[]>;
  loadIssueLinksJson?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
  ): Promise<string>;
  setIssueSummary?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    summary: string,
  ): Promise<IssueDetails>;
  setIssueSummaryJson?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    summary: string,
  ): Promise<string>;
  setIssueDescription?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    description: string | null,
  ): Promise<IssueDetails>;
  setIssueDescriptionJson?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    description: string | null,
  ): Promise<string>;
  setCustomFieldValue?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    fieldId: string,
    fieldType: string,
    value: unknown,
  ): Promise<CustomFieldValue>;
  setCustomFieldValueJson?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    fieldId: string,
    fieldType: string,
    valueJson: string,
  ): Promise<string>;
  applyCustomFieldEvent?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    fieldId: string,
    fieldType: string,
    eventId: string,
  ): Promise<CustomFieldValue>;
  applyCustomFieldEventJson?(
    serviceUrl: string,
    bearerToken: string,
    issueId: string,
    fieldId: string,
    fieldType: string,
    eventId: string,
  ): Promise<string>;
  loadMyWork?(
    serviceUrl: string,
    bearerToken: string,
    top: number,
  ): Promise<MyWork>;
  loadMyWorkJson?(
    serviceUrl: string,
    bearerToken: string,
    top: number,
  ): Promise<string>;
};

function module(): VelaRustModule {
  const rust = NativeModules.VelaRust as VelaRustModule | undefined;

  if (!rust) {
    throw new Error('Vela Rust bridge is unavailable');
  }

  return rust;
}

function decodeBridgeResponse<T>(json: string): T {
  const response = JSON.parse(json) as BridgeResponse<T>;

  if (response.status === 'ok') {
    return response.data;
  }

  throw new Error(response.message);
}

export async function discoverYouTrack(
  serviceUrl: string,
  bearerToken: string,
): Promise<YouTrackDiscovery> {
  const rust = module();

  if (rust.discover) {
    return rust.discover(serviceUrl, bearerToken);
  }

  if (rust.discoverJson) {
    return decodeBridgeResponse(
      await rust.discoverJson(serviceUrl, bearerToken),
    );
  }

  throw new Error('Vela Rust bridge has no supported discovery method');
}

export async function loadProjectSchema(
  serviceUrl: string,
  bearerToken: string,
  projectId: string,
): Promise<ProjectSchema> {
  const rust = module();

  if (rust.loadProjectSchema) {
    return rust.loadProjectSchema(serviceUrl, bearerToken, projectId);
  }

  if (rust.loadProjectSchemaJson) {
    return decodeBridgeResponse(
      await rust.loadProjectSchemaJson(serviceUrl, bearerToken, projectId),
    );
  }

  throw new Error('Vela Rust bridge has no supported project schema method');
}

export async function loadUsers(
  serviceUrl: string,
  bearerToken: string,
  skip = 0,
  top = 42,
): Promise<UserRef[]> {
  const normalizedSkip = Math.max(0, Math.trunc(skip));
  const normalizedTop = Math.max(1, Math.trunc(top));

  const rust = module();

  if (rust.loadUsers) {
    return rust.loadUsers(
      serviceUrl,
      bearerToken,
      normalizedSkip,
      normalizedTop,
    );
  }

  if (rust.loadUsersJson) {
    return decodeBridgeResponse(
      await rust.loadUsersJson(
        serviceUrl,
        bearerToken,
        normalizedSkip,
        normalizedTop,
      ),
    );
  }

  throw new Error('Vela Rust bridge has no supported users method');
}

export async function loadAgileBoards(
  serviceUrl: string,
  bearerToken: string,
  skip = 0,
  top = 42,
): Promise<AgileBoard[]> {
  const normalizedSkip = Math.max(0, Math.trunc(skip));
  const normalizedTop = Math.max(1, Math.trunc(top));

  const rust = module();

  if (rust.loadAgileBoards) {
    return rust.loadAgileBoards(
      serviceUrl,
      bearerToken,
      normalizedSkip,
      normalizedTop,
    );
  }

  if (rust.loadAgileBoardsJson) {
    return decodeBridgeResponse(
      await rust.loadAgileBoardsJson(
        serviceUrl,
        bearerToken,
        normalizedSkip,
        normalizedTop,
      ),
    );
  }

  throw new Error('Vela Rust bridge has no supported agile boards method');
}

export async function loadSavedQueries(
  serviceUrl: string,
  bearerToken: string,
  skip = 0,
  top = 42,
): Promise<SavedQuery[]> {
  const normalizedSkip = Math.max(0, Math.trunc(skip));
  const normalizedTop = Math.max(1, Math.trunc(top));

  const rust = module();

  if (rust.loadSavedQueries) {
    return rust.loadSavedQueries(
      serviceUrl,
      bearerToken,
      normalizedSkip,
      normalizedTop,
    );
  }

  if (rust.loadSavedQueriesJson) {
    return decodeBridgeResponse(
      await rust.loadSavedQueriesJson(
        serviceUrl,
        bearerToken,
        normalizedSkip,
        normalizedTop,
      ),
    );
  }

  throw new Error('Vela Rust bridge has no supported saved queries method');
}

export async function loadIssueDetails(
  serviceUrl: string,
  bearerToken: string,
  issueId: string,
): Promise<IssueDetails> {
  const rust = module();

  if (rust.loadIssueDetails) {
    return rust.loadIssueDetails(serviceUrl, bearerToken, issueId);
  }

  if (rust.loadIssueDetailsJson) {
    return decodeBridgeResponse(
      await rust.loadIssueDetailsJson(serviceUrl, bearerToken, issueId),
    );
  }

  throw new Error('Vela Rust bridge has no supported issue details method');
}

export async function loadIssueLinks(
  serviceUrl: string,
  bearerToken: string,
  issueId: string,
): Promise<IssueLink[]> {
  const rust = module();

  if (rust.loadIssueLinks) {
    return rust.loadIssueLinks(serviceUrl, bearerToken, issueId);
  }

  if (rust.loadIssueLinksJson) {
    return decodeBridgeResponse(
      await rust.loadIssueLinksJson(serviceUrl, bearerToken, issueId),
    );
  }

  throw new Error('Vela Rust bridge has no supported issue links method');
}

export async function setIssueSummary(
  serviceUrl: string,
  bearerToken: string,
  issueId: string,
  summary: string,
): Promise<IssueDetails> {
  const rust = module();

  if (rust.setIssueSummary) {
    return rust.setIssueSummary(serviceUrl, bearerToken, issueId, summary);
  }

  if (rust.setIssueSummaryJson) {
    return decodeBridgeResponse(
      await rust.setIssueSummaryJson(serviceUrl, bearerToken, issueId, summary),
    );
  }

  throw new Error('Vela Rust bridge has no supported summary update method');
}

export async function setIssueDescription(
  serviceUrl: string,
  bearerToken: string,
  issueId: string,
  description: string | null,
): Promise<IssueDetails> {
  const rust = module();

  if (rust.setIssueDescription) {
    return rust.setIssueDescription(
      serviceUrl,
      bearerToken,
      issueId,
      description,
    );
  }

  if (rust.setIssueDescriptionJson) {
    return decodeBridgeResponse(
      await rust.setIssueDescriptionJson(
        serviceUrl,
        bearerToken,
        issueId,
        description,
      ),
    );
  }

  throw new Error(
    'Vela Rust bridge has no supported description update method',
  );
}

export async function setCustomFieldValue(
  serviceUrl: string,
  bearerToken: string,
  issueId: string,
  fieldId: string,
  fieldType: string,
  value: unknown,
): Promise<CustomFieldValue> {
  const rust = module();

  if (rust.setCustomFieldValue) {
    return rust.setCustomFieldValue(
      serviceUrl,
      bearerToken,
      issueId,
      fieldId,
      fieldType,
      value,
    );
  }

  if (rust.setCustomFieldValueJson) {
    return decodeBridgeResponse(
      await rust.setCustomFieldValueJson(
        serviceUrl,
        bearerToken,
        issueId,
        fieldId,
        fieldType,
        JSON.stringify(value),
      ),
    );
  }

  throw new Error(
    'Vela Rust bridge has no supported custom field update method',
  );
}

export async function applyCustomFieldEvent(
  serviceUrl: string,
  bearerToken: string,
  issueId: string,
  fieldId: string,
  fieldType: string,
  eventId: string,
): Promise<CustomFieldValue> {
  const rust = module();

  if (rust.applyCustomFieldEvent) {
    return rust.applyCustomFieldEvent(
      serviceUrl,
      bearerToken,
      issueId,
      fieldId,
      fieldType,
      eventId,
    );
  }

  if (rust.applyCustomFieldEventJson) {
    return decodeBridgeResponse(
      await rust.applyCustomFieldEventJson(
        serviceUrl,
        bearerToken,
        issueId,
        fieldId,
        fieldType,
        eventId,
      ),
    );
  }

  throw new Error('Vela Rust bridge has no supported field event method');
}

export async function loadMyWork(
  serviceUrl: string,
  bearerToken: string,
  top = 50,
): Promise<MyWork> {
  const rust = module();

  if (rust.loadMyWork) {
    return rust.loadMyWork(serviceUrl, bearerToken, top);
  }

  if (rust.loadMyWorkJson) {
    return decodeBridgeResponse(
      await rust.loadMyWorkJson(serviceUrl, bearerToken, top),
    );
  }

  throw new Error('Vela Rust bridge has no supported My Work method');
}
