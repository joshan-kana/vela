import React, { useEffect, useMemo, useState } from 'react';
import {
  ActionSheetIOS,
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';

import {
  applyCustomFieldEvent,
  loadIssueDetails,
  loadIssueLinks,
  loadProjectSchema,
  setCustomFieldValue,
  setIssueDescription,
  setIssueSummary,
  type BundleValue,
  type CustomFieldValue,
  type IssueDetails,
  type IssueLink,
  type ProjectCustomField,
  type ProjectSchema,
} from '../native/VelaRust';

export type InspectorPalette = {
  background: string;
  separator: string;
  selection: string;
  text: string;
  secondaryText: string;
  accent: string;
};

type Props = {
  serviceUrl: string;
  bearerToken: string;
  issueId: string;
  palette: InspectorPalette;
  onBack(): void;
  onIssueChanged(issue: IssueDetails): void;
};

export default function IssueInspector({
  serviceUrl,
  bearerToken,
  issueId,
  palette,
  onBack,
  onIssueChanged,
}: Props) {
  const [details, setDetails] = useState<IssueDetails | null>(null);
  const [schema, setSchema] = useState<ProjectSchema | null>(null);
  const [links, setLinks] = useState<IssueLink[]>([]);
  const [summary, setSummary] = useState('');
  const [description, setDescription] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    async function load() {
      setLoading(true);
      setError(null);

      try {
        const issue = await loadIssueDetails(serviceUrl, bearerToken, issueId);
        const [projectSchema, issueLinks] = await Promise.all([
          loadProjectSchema(serviceUrl, bearerToken, issue.project.id),
          loadIssueLinks(serviceUrl, bearerToken, issueId),
        ]);

        if (!active) {
          return;
        }

        setDetails(issue);
        setSchema(projectSchema);
        setLinks(issueLinks);
        setSummary(issue.summary);
        setDescription(issue.description ?? '');
      } catch (loadError) {
        if (active) {
          setError(message(loadError, 'Unable to load the issue'));
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    load();

    return () => {
      active = false;
    };
  }, [bearerToken, issueId, serviceUrl]);

  const fields = useMemo(() => {
    if (!details) {
      return [];
    }

    return [...details.custom_fields].sort((left, right) => {
      const leftRank = semanticRank(left, schema);
      const rightRank = semanticRank(right, schema);
      return leftRank - rightRank;
    });
  }, [details, schema]);

  async function saveSummary() {
    if (!details || saving || summary === details.summary) {
      return;
    }

    setSaving('summary');
    setError(null);

    try {
      const updated = await setIssueSummary(
        serviceUrl,
        bearerToken,
        details.id,
        summary,
      );
      replaceDetails(updated);
    } catch (saveError) {
      setSummary(details.summary);
      setError(message(saveError, 'Unable to update the summary'));
    } finally {
      setSaving(null);
    }
  }

  async function saveDescription() {
    if (!details || saving || description === (details.description ?? '')) {
      return;
    }

    setSaving('description');
    setError(null);

    try {
      const updated = await setIssueDescription(
        serviceUrl,
        bearerToken,
        details.id,
        description.trim().length === 0 ? null : description,
      );
      replaceDetails(updated);
    } catch (saveError) {
      setDescription(details.description ?? '');
      setError(message(saveError, 'Unable to update the description'));
    } finally {
      setSaving(null);
    }
  }

  async function updateField(field: CustomFieldValue, value: unknown) {
    if (!details || saving) {
      return;
    }

    setSaving(field.id);
    setError(null);

    try {
      const updated = await setCustomFieldValue(
        serviceUrl,
        bearerToken,
        details.id,
        field.id,
        field.field_type,
        value,
      );
      replaceField(updated);
    } catch (saveError) {
      setError(message(saveError, `Unable to update ${field.name}`));
    } finally {
      setSaving(null);
    }
  }

  async function applyEvent(field: CustomFieldValue, eventId: string) {
    if (!details || saving) {
      return;
    }

    setSaving(field.id);
    setError(null);

    try {
      const updated = await applyCustomFieldEvent(
        serviceUrl,
        bearerToken,
        details.id,
        field.id,
        field.field_type,
        eventId,
      );
      replaceField(updated);
    } catch (saveError) {
      setError(message(saveError, `Unable to update ${field.name}`));
    } finally {
      setSaving(null);
    }
  }

  function replaceDetails(updated: IssueDetails) {
    setDetails(updated);
    setSummary(updated.summary);
    setDescription(updated.description ?? '');
    onIssueChanged(updated);
  }

  function replaceField(updated: CustomFieldValue) {
    setDetails(current => {
      if (!current) {
        return current;
      }

      const next = {
        ...current,
        custom_fields: current.custom_fields.map(field =>
          field.id === updated.id ? updated : field,
        ),
      };
      onIssueChanged(next);
      return next;
    });
  }

  return (
    <View style={styles.root}>
      <View style={[styles.toolbar, { borderColor: palette.separator }]}>
        <Pressable
          accessibilityRole="button"
          onPress={onBack}
          style={({ pressed }) => [
            styles.backButton,
            { backgroundColor: palette.selection },
            pressed && styles.pressed,
          ]}
        >
          <Text style={{ color: palette.text }}>‹ My Work</Text>
        </Pressable>
        {details ? (
          <Text style={[styles.issueId, { color: palette.secondaryText }]}>
            {details.id_readable}
          </Text>
        ) : null}
      </View>

      {loading ? (
        <View style={styles.centered}>
          <ActivityIndicator />
        </View>
      ) : error && !details ? (
        <View style={styles.centered}>
          <Text style={styles.error}>{error}</Text>
        </View>
      ) : details ? (
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
        >
          <Text style={[styles.eyebrow, { color: palette.secondaryText }]}>
            {details.project.name} · {details.project.short_name}
          </Text>

          <Text style={[styles.label, { color: palette.secondaryText }]}>
            Summary
          </Text>
          <TextInput
            accessibilityLabel="Issue summary"
            editable={saving !== 'summary'}
            onChangeText={setSummary}
            onEndEditing={() => saveSummary()}
            onSubmitEditing={() => saveSummary()}
            returnKeyType="done"
            style={[
              styles.summaryInput,
              {
                borderColor: palette.separator,
                color: palette.text,
              },
            ]}
            value={summary}
          />

          <Text style={[styles.label, { color: palette.secondaryText }]}>
            Description
          </Text>
          <TextInput
            accessibilityLabel="Issue description"
            editable={saving !== 'description'}
            multiline
            onChangeText={setDescription}
            style={[
              styles.descriptionInput,
              {
                borderColor: palette.separator,
                color: palette.text,
              },
            ]}
            textAlignVertical="top"
            value={description}
          />
          <Pressable
            accessibilityRole="button"
            disabled={
              saving !== null || description === (details.description ?? '')
            }
            onPress={() => saveDescription()}
            style={({ pressed }) => [
              styles.saveButton,
              { backgroundColor: palette.accent },
              (saving !== null ||
                description === (details.description ?? '')) &&
                styles.disabled,
              pressed && styles.pressed,
            ]}
          >
            <Text style={styles.saveButtonText}>
              {saving === 'description' ? 'Saving…' : 'Save description'}
            </Text>
          </Pressable>

          {error ? <Text style={styles.error}>{error}</Text> : null}

          <Section title="Fields" palette={palette}>
            {fields.map(field => (
              <FieldEditor
                key={field.id}
                field={field}
                palette={palette}
                projectField={projectFieldFor(field, schema)}
                saving={saving === field.id}
                onApplyEvent={eventId => applyEvent(field, eventId)}
                onChange={value => updateField(field, value)}
              />
            ))}
          </Section>

          <Section title="Links" palette={palette}>
            {links.length === 0 ? (
              <Text style={{ color: palette.secondaryText }}>
                No issue links.
              </Text>
            ) : (
              links.flatMap(link =>
                link.issues.map(linked => (
                  <View
                    key={`${link.id}:${linked.id}`}
                    style={[styles.linkRow, { borderColor: palette.separator }]}
                  >
                    <Text
                      style={[
                        styles.linkDirection,
                        { color: palette.secondaryText },
                      ]}
                    >
                      {linkLabel(link)}
                    </Text>
                    <Text
                      style={[styles.linkId, { color: palette.secondaryText }]}
                    >
                      {linked.id_readable}
                    </Text>
                    <Text style={[styles.linkSummary, { color: palette.text }]}>
                      {linked.summary}
                    </Text>
                  </View>
                )),
              )
            )}
          </Section>
        </ScrollView>
      ) : null}
    </View>
  );
}

function Section({
  title,
  palette,
  children,
}: {
  title: string;
  palette: InspectorPalette;
  children: React.ReactNode;
}) {
  return (
    <View style={styles.section}>
      <Text style={[styles.sectionTitle, { color: palette.text }]}>
        {title}
      </Text>
      {children}
    </View>
  );
}

function FieldEditor({
  field,
  projectField,
  palette,
  saving,
  onChange,
  onApplyEvent,
}: {
  field: CustomFieldValue;
  projectField: ProjectCustomField | null;
  palette: InspectorPalette;
  saving: boolean;
  onChange(value: unknown): void;
  onApplyEvent(eventId: string): void;
}) {
  const [draft, setDraft] = useState(editableText(field.value));
  const bundle = projectField?.bundle;
  const isMulti = projectField?.field.field_type.is_multi_value ?? false;

  useEffect(() => {
    setDraft(editableText(field.value));
  }, [field.value]);

  if (field.possible_events.length > 0) {
    return (
      <FieldRow field={field} palette={palette}>
        <ChoiceButton
          label={displayValue(field.value)}
          palette={palette}
          disabled={saving}
          onPress={() =>
            choose(
              field.name,
              field.possible_events.map(event => ({
                label: event.presentation,
                onSelect: () => onApplyEvent(event.id),
              })),
            )
          }
        />
      </FieldRow>
    );
  }

  if (bundle && bundle.values.length > 0) {
    if (isMulti) {
      return (
        <MultiBundleField
          field={field}
          values={bundle.values}
          palette={palette}
          disabled={saving}
          onChange={onChange}
        />
      );
    }

    return (
      <FieldRow field={field} palette={palette}>
        <ChoiceButton
          label={displayValue(field.value)}
          palette={palette}
          disabled={saving}
          onPress={() =>
            choose(field.name, [
              ...(projectField?.can_be_empty
                ? [{ label: 'None', onSelect: () => onChange(null) }]
                : []),
              ...bundle.values
                .filter(value => value.archived !== true)
                .map(value => ({
                  label: value.display_name,
                  onSelect: () => onChange({ id: value.id }),
                })),
            ])
          }
        />
      </FieldRow>
    );
  }

  if (typeof field.value === 'boolean') {
    return (
      <FieldRow field={field} palette={palette}>
        <Switch
          accessibilityLabel={field.name}
          disabled={saving}
          onValueChange={onChange}
          value={field.value}
        />
      </FieldRow>
    );
  }

  if (isDateField(field, projectField)) {
    return (
      <FieldRow field={field} palette={palette}>
        <View style={styles.inlineEditor}>
          <TextInput
            accessibilityLabel={`${field.name} date`}
            autoCapitalize="none"
            editable={!saving}
            onChangeText={setDraft}
            placeholder="YYYY-MM-DD"
            style={[
              styles.fieldInput,
              { borderColor: palette.separator, color: palette.text },
            ]}
            value={draft}
          />
          <SmallSave
            palette={palette}
            disabled={saving || draft === editableText(field.value)}
            onPress={() => {
              if (draft.trim() === '') {
                onChange(null);
                return;
              }

              const timestamp = parseDate(draft);
              if (timestamp === null) {
                Alert.alert('Invalid date', 'Use the YYYY-MM-DD format.');
                return;
              }
              onChange(timestamp);
            }}
          />
        </View>
      </FieldRow>
    );
  }

  if (
    field.value === null ||
    typeof field.value === 'string' ||
    typeof field.value === 'number' ||
    isTextValue(field.value)
  ) {
    return (
      <FieldRow field={field} palette={palette}>
        <View style={styles.inlineEditor}>
          <TextInput
            accessibilityLabel={field.name}
            editable={!saving}
            onChangeText={setDraft}
            style={[
              styles.fieldInput,
              { borderColor: palette.separator, color: palette.text },
            ]}
            value={draft}
          />
          <SmallSave
            palette={palette}
            disabled={saving || draft === editableText(field.value)}
            onPress={() => onChange(valueFromDraft(field.value, draft))}
          />
        </View>
      </FieldRow>
    );
  }

  return (
    <FieldRow field={field} palette={palette}>
      <Text style={{ color: palette.text }}>{displayValue(field.value)}</Text>
    </FieldRow>
  );
}

function MultiBundleField({
  field,
  values,
  palette,
  disabled,
  onChange,
}: {
  field: CustomFieldValue;
  values: BundleValue[];
  palette: InspectorPalette;
  disabled: boolean;
  onChange(value: unknown): void;
}) {
  const selectedIds = selectedValueIds(field.value);

  return (
    <FieldRow field={field} palette={palette}>
      <ChoiceButton
        label={displayValue(field.value)}
        palette={palette}
        disabled={disabled}
        onPress={() =>
          choose(
            field.name,
            values
              .filter(value => value.archived !== true)
              .map(value => ({
                label: `${selectedIds.has(value.id) ? '✓ ' : ''}${
                  value.display_name
                }`,
                onSelect: () => {
                  const next = new Set(selectedIds);
                  if (next.has(value.id)) {
                    next.delete(value.id);
                  } else {
                    next.add(value.id);
                  }

                  onChange([...next].map(id => ({ id })));
                },
              })),
          )
        }
      />
    </FieldRow>
  );
}

function FieldRow({
  field,
  palette,
  children,
}: {
  field: CustomFieldValue;
  palette: InspectorPalette;
  children: React.ReactNode;
}) {
  return (
    <View style={[styles.fieldRow, { borderColor: palette.separator }]}>
      <View style={styles.fieldLabelBlock}>
        <Text style={[styles.fieldName, { color: palette.text }]}>
          {field.name}
        </Text>
        <Text style={[styles.fieldType, { color: palette.secondaryText }]}>
          {field.field_type}
        </Text>
      </View>
      <View style={styles.fieldEditor}>{children}</View>
    </View>
  );
}

function ChoiceButton({
  label,
  palette,
  disabled,
  onPress,
}: {
  label: string;
  palette: InspectorPalette;
  disabled: boolean;
  onPress(): void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.choiceButton,
        {
          backgroundColor: palette.selection,
          borderColor: palette.separator,
        },
        disabled && styles.disabled,
        pressed && styles.pressed,
      ]}
    >
      <Text numberOfLines={1} style={{ color: palette.text }}>
        {label || 'None'}
      </Text>
    </Pressable>
  );
}

function SmallSave({
  palette,
  disabled,
  onPress,
}: {
  palette: InspectorPalette;
  disabled: boolean;
  onPress(): void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.smallSave,
        { backgroundColor: palette.accent },
        disabled && styles.disabled,
        pressed && styles.pressed,
      ]}
    >
      <Text style={styles.saveButtonText}>Save</Text>
    </Pressable>
  );
}

function choose(
  title: string,
  options: Array<{ label: string; onSelect(): void }>,
) {
  if (options.length === 0) {
    return;
  }

  if (Platform.OS === 'ios') {
    ActionSheetIOS.showActionSheetWithOptions(
      {
        title,
        options: ['Cancel', ...options.map(option => option.label)],
        cancelButtonIndex: 0,
      },
      index => {
        if (index > 0) {
          options[index - 1]?.onSelect();
        }
      },
    );
    return;
  }

  Alert.alert(
    title,
    undefined,
    [
      ...options.map(option => ({
        text: option.label,
        onPress: option.onSelect,
      })),
      { text: 'Cancel', style: 'cancel' },
    ],
    { cancelable: true },
  );
}

function projectFieldFor(
  field: CustomFieldValue,
  schema: ProjectSchema | null,
): ProjectCustomField | null {
  if (!schema) {
    return null;
  }

  return (
    schema.custom_fields.find(candidate => candidate.id === field.id) ??
    schema.custom_fields.find(
      candidate => candidate.field.name === field.name,
    ) ??
    null
  );
}

function semanticRank(
  field: CustomFieldValue,
  schema: ProjectSchema | null,
): number {
  const projectField = projectFieldFor(field, schema);
  const valueType =
    projectField?.field.field_type.value_type.toLowerCase() ?? '';
  const name = field.name.toLowerCase();
  const aliases = projectField?.field.aliases?.toLowerCase() ?? '';

  if (
    valueType.includes('state') ||
    field.field_type.toLowerCase().includes('state')
  ) {
    return 0;
  }
  if (name === 'priority' || aliases.includes('priority')) {
    return 1;
  }
  if (isDateField(field, projectField)) {
    return 2;
  }
  return 3;
}

function isDateField(
  field: CustomFieldValue,
  projectField: ProjectCustomField | null,
): boolean {
  const valueType =
    projectField?.field.field_type.value_type.toLowerCase() ?? '';
  return (
    field.field_type.toLowerCase().includes('dateissuecustomfield') ||
    valueType === 'date'
  );
}

function displayValue(value: unknown): string {
  if (value === null || value === undefined) {
    return 'None';
  }
  if (Array.isArray(value)) {
    return value.map(displayValue).join(', ') || 'None';
  }
  if (typeof value === 'object') {
    const object = value as Record<string, unknown>;
    for (const key of [
      'presentation',
      'name',
      'localizedName',
      'fullName',
      'login',
      'text',
    ]) {
      if (typeof object[key] === 'string' && object[key]) {
        return object[key] as string;
      }
    }
    return JSON.stringify(value);
  }
  if (typeof value === 'number' && value > 100000000000) {
    return formatDate(value);
  }
  return String(value);
}

function editableText(value: unknown): string {
  if (value === null || value === undefined) {
    return '';
  }
  if (typeof value === 'string' || typeof value === 'number') {
    return String(value);
  }
  if (isTextValue(value)) {
    return value.text;
  }
  return displayValue(value);
}

function valueFromDraft(current: unknown, draft: string): unknown {
  if (typeof current === 'number') {
    const value = Number(draft);
    return Number.isFinite(value) ? value : current;
  }
  if (isTextValue(current)) {
    return { ...current, text: draft };
  }
  return draft;
}

function isTextValue(
  value: unknown,
): value is Record<string, unknown> & { text: string } {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as Record<string, unknown>).text === 'string'
  );
}

function selectedValueIds(value: unknown): Set<string> {
  if (!Array.isArray(value)) {
    return new Set();
  }

  return new Set(
    value.flatMap(item => {
      if (
        typeof item === 'object' &&
        item !== null &&
        typeof (item as Record<string, unknown>).id === 'string'
      ) {
        return [(item as Record<string, string>).id];
      }
      return [];
    }),
  );
}

function formatDate(timestamp: number): string {
  return new Date(timestamp).toISOString().slice(0, 10);
}

function parseDate(value: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }

  const timestamp = Date.parse(`${value}T00:00:00.000Z`);
  return Number.isNaN(timestamp) ? null : timestamp;
}

function linkLabel(link: IssueLink): string {
  if (!link.link_type.directed) {
    return link.link_type.source_to_target;
  }

  return link.direction === 'OUTWARD'
    ? link.link_type.source_to_target
    : (link.link_type.target_to_source ?? link.link_type.source_to_target);
}

function message(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  toolbar: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 12,
    paddingBottom: 12,
  },
  backButton: {
    borderRadius: 7,
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  issueId: {
    fontSize: 12,
    fontWeight: '600',
  },
  centered: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
  scrollContent: {
    paddingBottom: 48,
    paddingTop: 20,
  },
  eyebrow: {
    fontSize: 13,
    marginBottom: 10,
  },
  label: {
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 6,
    marginTop: 12,
    textTransform: 'uppercase',
  },
  summaryInput: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    fontSize: 22,
    fontWeight: '600',
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  descriptionInput: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    fontSize: 14,
    minHeight: 120,
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  saveButton: {
    alignItems: 'center',
    alignSelf: 'flex-start',
    borderRadius: 7,
    marginTop: 8,
    minHeight: 34,
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  saveButtonText: {
    color: '#ffffff',
    fontSize: 13,
    fontWeight: '600',
  },
  section: {
    marginTop: 28,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 8,
  },
  fieldRow: {
    alignItems: 'center',
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    minHeight: 54,
    paddingVertical: 8,
  },
  fieldLabelBlock: {
    paddingRight: 16,
    width: 190,
  },
  fieldName: {
    fontSize: 14,
    fontWeight: '500',
  },
  fieldType: {
    fontSize: 10,
    marginTop: 2,
  },
  fieldEditor: {
    alignItems: 'flex-end',
    flex: 1,
  },
  choiceButton: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    maxWidth: 420,
    minWidth: 160,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  inlineEditor: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 8,
    maxWidth: 460,
    width: '100%',
  },
  fieldInput: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    flex: 1,
    minHeight: 34,
    paddingHorizontal: 9,
    paddingVertical: 7,
  },
  smallSave: {
    borderRadius: 7,
    minHeight: 34,
    justifyContent: 'center',
    paddingHorizontal: 12,
  },
  disabled: {
    opacity: 0.45,
  },
  pressed: {
    opacity: 0.75,
  },
  error: {
    color: '#d93025',
    fontSize: 13,
    marginTop: 10,
  },
  linkRow: {
    alignItems: 'center',
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    minHeight: 42,
  },
  linkDirection: {
    fontSize: 12,
    width: 110,
  },
  linkId: {
    fontSize: 12,
    width: 88,
  },
  linkSummary: {
    flex: 1,
    fontSize: 14,
  },
});
