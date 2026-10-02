import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Linking,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  useColorScheme,
  View,
} from 'react-native';

import IssueInspector from './src/components/IssueInspector';
import {
  beginOAuth,
  completeOAuth,
  deleteAccount,
  listAccounts,
  savePermanentTokenAccount,
  withConnection,
  type Connection,
  type StoredAccount,
} from './src/native/AccountStore';
import {
  loadMyWork,
  type IssueDetails,
  type MyWork,
} from './src/native/VelaRust';

const ISSUE_ROW_HEIGHT = 42;
const OAUTH_CALLBACK_PREFIX = 'io.github.joshankana.vela:/oauth/callback';

function App() {
  const dark = useColorScheme() === 'dark';
  const palette = dark ? darkPalette : lightPalette;

  const tokenInputRef = useRef<TextInput>(null);
  const tokenValueRef = useRef('');
  const [serviceUrl, setServiceUrl] = useState('');
  const [oauthClientId, setOAuthClientId] = useState('');
  const [oauthHubUrl, setOAuthHubUrl] = useState('');
  const [oauthScope, setOAuthScope] = useState('');
  const handledOAuthCallbackRef = useRef<string | null>(null);
  const [accounts, setAccounts] = useState<StoredAccount[]>([]);
  const [accountsLoading, setAccountsLoading] = useState(true);
  const [work, setWork] = useState<MyWork | null>(null);
  const [session, setSession] = useState<Connection | null>(null);
  const [selectedIssueId, setSelectedIssueId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [connecting, setConnecting] = useState(false);

  useEffect(() => {
    let active = true;

    listAccounts()
      .then(stored => {
        if (active) {
          setAccounts(stored);
        }
      })
      .catch(accountError => {
        if (active) {
          setError(message(accountError, 'Unable to load saved accounts'));
        }
      })
      .finally(() => {
        if (active) {
          setAccountsLoading(false);
        }
      });

    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    async function finishOAuthCallback(callbackUrl: string) {
      setConnecting(true);
      setError(null);

      try {
        const account = await completeOAuth(callbackUrl);
        const connection: Connection = {
          service_url: account.service_url,
          account_id: account.id,
        };
        const loadedWork = await withConnection(connection, loadMyWork);

        setAccounts(current =>
          [...current.filter(item => item.id !== account.id), account].sort(
            (left, right) => left.service_url.localeCompare(right.service_url),
          ),
        );
        setServiceUrl(account.service_url);
        setWork(loadedWork);
        setSession(connection);
      } catch (oauthError) {
        setError(message(oauthError, 'Unable to complete OAuth'));
      } finally {
        setConnecting(false);
      }
    }

    function handleUrl(url: string | null) {
      if (
        url?.startsWith(OAUTH_CALLBACK_PREFIX) &&
        handledOAuthCallbackRef.current !== url
      ) {
        handledOAuthCallbackRef.current = url;
        finishOAuthCallback(url);
      }
    }

    const subscription = Linking.addEventListener('url', event => {
      handleUrl(event.url);
    });

    Linking.getInitialURL().then(handleUrl);

    return () => {
      subscription.remove();
    };
  }, []);

  async function connect() {
    const trimmedUrl = serviceUrl.trim();
    if (!trimmedUrl || connecting) {
      return;
    }

    setConnecting(true);
    setError(null);

    const enteredToken = tokenValueRef.current.trim();

    try {
      const loadedWork = await loadMyWork(trimmedUrl, enteredToken);
      let account: StoredAccount | null = null;

      if (enteredToken) {
        account = await savePermanentTokenAccount(trimmedUrl, enteredToken);
        rememberAccount(account);
      }

      setWork(loadedWork);
      setSession({
        service_url: trimmedUrl,
        account_id: account?.id ?? null,
      });
      tokenValueRef.current = '';
      tokenInputRef.current?.clear();
    } catch (connectionError) {
      setWork(null);
      setError(message(connectionError, 'Unable to connect to YouTrack'));
    } finally {
      setConnecting(false);
    }
  }

  async function connectOAuth() {
    const trimmedUrl = serviceUrl.trim();
    const trimmedClientId = oauthClientId.trim();

    if (!trimmedUrl || !trimmedClientId || connecting) {
      return;
    }

    setConnecting(true);
    setError(null);

    try {
      const start = await beginOAuth(
        trimmedUrl,
        trimmedClientId,
        oauthHubUrl.trim() || null,
        oauthScope.trim() || null,
      );
      await Linking.openURL(start.authorization_url);
    } catch (oauthError) {
      setError(message(oauthError, 'Unable to start OAuth'));
    } finally {
      setConnecting(false);
    }
  }

  async function activateStoredAccount(account: StoredAccount) {
    const connection: Connection = {
      service_url: account.service_url,
      account_id: account.id,
    };
    const loadedWork = await withConnection(connection, loadMyWork);

    setServiceUrl(account.service_url);
    setWork(loadedWork);
    setSession(connection);
  }

  async function connectStored(account: StoredAccount) {
    if (connecting) {
      return;
    }

    setConnecting(true);
    setError(null);

    try {
      await activateStoredAccount(account);
    } catch (connectionError) {
      setWork(null);
      setError(message(connectionError, 'Unable to connect to YouTrack'));
    } finally {
      setConnecting(false);
    }
  }

  async function forgetAccount(account: StoredAccount) {
    try {
      await deleteAccount(account.id);
      setAccounts(current => current.filter(item => item.id !== account.id));
    } catch (accountError) {
      setError(message(accountError, 'Unable to forget the account'));
    }
  }

  function rememberAccount(account: StoredAccount) {
    setAccounts(current =>
      [...current.filter(item => item.id !== account.id), account].sort(
        (left, right) => left.service_url.localeCompare(right.service_url),
      ),
    );
  }

  function disconnect() {
    setSelectedIssueId(null);
    setSession(null);
    setWork(null);
  }

  return (
    <View style={[styles.window, { backgroundColor: palette.background }]}>
      <StatusBar barStyle={dark ? 'light-content' : 'dark-content'} />

      <View
        style={[
          styles.sidebar,
          {
            backgroundColor: palette.sidebar,
            borderColor: palette.separator,
          },
        ]}
      >
        <Text style={[styles.appName, { color: palette.text }]}>Vela</Text>

        <View style={styles.navigation}>
          <View
            style={[
              styles.navigationItem,
              { backgroundColor: palette.selection },
            ]}
          >
            <Text style={[styles.navigationText, { color: palette.text }]}>
              My Work
            </Text>
          </View>

          <View style={styles.navigationItem}>
            <Text
              style={[styles.navigationText, { color: palette.secondaryText }]}
            >
              Projects
            </Text>
          </View>
        </View>
      </View>

      <View style={styles.content}>
        {selectedIssueId && session ? (
          <IssueInspector
            connection={session}
            issueId={selectedIssueId}
            onBack={() => setSelectedIssueId(null)}
            onIssueChanged={(updated: IssueDetails) => {
              setWork(current =>
                current
                  ? {
                      ...current,
                      issues: current.issues.map(issue =>
                        issue.id === updated.id
                          ? {
                              ...issue,
                              summary: updated.summary,
                              resolved_at: updated.resolved_at,
                            }
                          : issue,
                      ),
                    }
                  : current,
              );
            }}
            palette={palette}
          />
        ) : (
          <>
            <Text style={[styles.heading, { color: palette.text }]}>
              My Work
            </Text>

            {work ? (
              <View style={styles.work}>
                <View
                  style={[
                    styles.accountBar,
                    { borderColor: palette.separator },
                  ]}
                >
                  <Text style={[styles.accountName, { color: palette.text }]}>
                    {work.user.full_name}
                  </Text>
                  <View style={styles.accountIdentity}>
                    <Text style={{ color: palette.secondaryText }}>
                      {work.user.login}
                      {work.user.guest ? ' · Guest access' : ''}
                    </Text>
                    <Pressable
                      accessibilityRole="button"
                      onPress={disconnect}
                      style={({ pressed }) => [
                        styles.textButton,
                        pressed && styles.buttonPressed,
                      ]}
                    >
                      <Text style={{ color: palette.accent }}>Disconnect</Text>
                    </Pressable>
                  </View>
                </View>

                <FlatList
                  initialNumToRender={20}
                  maxToRenderPerBatch={20}
                  windowSize={5}
                  removeClippedSubviews
                  getItemLayout={(_, index) => ({
                    length: ISSUE_ROW_HEIGHT,
                    offset: ISSUE_ROW_HEIGHT * index,
                    index,
                  })}
                  contentContainerStyle={
                    work.issues.length === 0 ? styles.emptyList : undefined
                  }
                  data={work.issues}
                  keyExtractor={issue => issue.id}
                  ListEmptyComponent={
                    <Text style={{ color: palette.secondaryText }}>
                      No unresolved issues assigned to you.
                    </Text>
                  }
                  renderItem={({ item }) => (
                    <Pressable
                      accessibilityLabel={`Open ${item.id_readable}`}
                      accessibilityRole="button"
                      onPress={() => setSelectedIssueId(item.id)}
                      style={({ pressed }) => [
                        styles.issueRow,
                        { borderColor: palette.separator },
                        pressed && styles.buttonPressed,
                      ]}
                    >
                      <Text
                        style={[styles.issueMarker, { color: palette.accent }]}
                      >
                        ○
                      </Text>
                      <Text
                        style={[
                          styles.issueId,
                          { color: palette.secondaryText },
                        ]}
                      >
                        {item.id_readable}
                      </Text>
                      <Text
                        numberOfLines={1}
                        style={[styles.issueSummary, { color: palette.text }]}
                      >
                        {item.summary}
                      </Text>
                    </Pressable>
                  )}
                />
              </View>
            ) : (
              <View style={styles.connectionState}>
                <Text style={[styles.connectionTitle, { color: palette.text }]}>
                  Connect to YouTrack
                </Text>
                <Text
                  style={[
                    styles.connectionDescription,
                    { color: palette.secondaryText },
                  ]}
                >
                  Use OAuth for a preregistered public client, or connect with a
                  permanent token or guest access.
                </Text>

                <View style={styles.form}>
                  {accountsLoading ? (
                    <ActivityIndicator />
                  ) : accounts.length > 0 ? (
                    <View style={styles.savedAccounts}>
                      <Text
                        style={[
                          styles.savedAccountsTitle,
                          { color: palette.secondaryText },
                        ]}
                      >
                        Saved accounts
                      </Text>
                      {accounts.map(account => (
                        <View
                          key={account.id}
                          style={[
                            styles.savedAccountRow,
                            { borderColor: palette.separator },
                          ]}
                        >
                          <Pressable
                            accessibilityLabel={`Connect ${account.service_url}`}
                            accessibilityRole="button"
                            disabled={connecting}
                            onPress={() => {
                              connectStored(account);
                            }}
                            style={({ pressed }) => [
                              styles.savedAccountButton,
                              pressed && styles.buttonPressed,
                            ]}
                          >
                            <Text
                              numberOfLines={1}
                              style={{ color: palette.text }}
                            >
                              {account.service_url}
                            </Text>
                          </Pressable>
                          <Pressable
                            accessibilityLabel={`Forget ${account.service_url}`}
                            accessibilityRole="button"
                            disabled={connecting}
                            onPress={() => {
                              forgetAccount(account);
                            }}
                            style={({ pressed }) => [
                              styles.forgetButton,
                              pressed && styles.buttonPressed,
                            ]}
                          >
                            <Text style={{ color: palette.secondaryText }}>
                              Forget
                            </Text>
                          </Pressable>
                        </View>
                      ))}
                    </View>
                  ) : null}

                  <TextInput
                    accessibilityLabel="YouTrack address"
                    autoCapitalize="none"
                    autoCorrect={false}
                    onChangeText={setServiceUrl}
                    onSubmitEditing={connect}
                    placeholder="https://youtrack.example.com"
                    placeholderTextColor={palette.secondaryText}
                    style={[
                      styles.input,
                      {
                        borderColor: palette.separator,
                        color: palette.text,
                      },
                    ]}
                    value={serviceUrl}
                  />
                  <TextInput
                    accessibilityLabel="OAuth client ID"
                    autoCapitalize="none"
                    autoCorrect={false}
                    onChangeText={setOAuthClientId}
                    placeholder="OAuth client ID"
                    placeholderTextColor={palette.secondaryText}
                    style={[
                      styles.input,
                      {
                        borderColor: palette.separator,
                        color: palette.text,
                      },
                    ]}
                    value={oauthClientId}
                  />
                  <TextInput
                    accessibilityLabel="Hub address"
                    autoCapitalize="none"
                    autoCorrect={false}
                    onChangeText={setOAuthHubUrl}
                    placeholder="Hub address override (optional)"
                    placeholderTextColor={palette.secondaryText}
                    style={[
                      styles.input,
                      {
                        borderColor: palette.separator,
                        color: palette.text,
                      },
                    ]}
                    value={oauthHubUrl}
                  />
                  <TextInput
                    accessibilityLabel="OAuth scope"
                    autoCapitalize="none"
                    autoCorrect={false}
                    onChangeText={setOAuthScope}
                    placeholder="OAuth scope override (optional)"
                    placeholderTextColor={palette.secondaryText}
                    style={[
                      styles.input,
                      {
                        borderColor: palette.separator,
                        color: palette.text,
                      },
                    ]}
                    value={oauthScope}
                  />
                  <Pressable
                    accessibilityLabel="Connect with OAuth"
                    accessibilityRole="button"
                    disabled={
                      !serviceUrl.trim() || !oauthClientId.trim() || connecting
                    }
                    onPress={() => {
                      connectOAuth();
                    }}
                    style={({ pressed }) => [
                      styles.button,
                      { backgroundColor: palette.accent },
                      (!serviceUrl.trim() ||
                        !oauthClientId.trim() ||
                        connecting) &&
                        styles.buttonDisabled,
                      pressed && styles.buttonPressed,
                    ]}
                  >
                    <Text style={styles.buttonText}>Connect with OAuth</Text>
                  </Pressable>

                  <Text
                    style={[
                      styles.authDivider,
                      { color: palette.secondaryText },
                    ]}
                  >
                    or
                  </Text>
                  <TextInput
                    ref={tokenInputRef}
                    accessibilityLabel="Permanent token"
                    autoCapitalize="none"
                    autoCorrect={false}
                    onChangeText={value => {
                      tokenValueRef.current = value;
                    }}
                    onSubmitEditing={connect}
                    placeholder="Permanent token (optional)"
                    placeholderTextColor={palette.secondaryText}
                    secureTextEntry
                    style={[
                      styles.input,
                      {
                        borderColor: palette.separator,
                        color: palette.text,
                      },
                    ]}
                  />

                  {error ? <Text style={styles.errorText}>{error}</Text> : null}

                  <Pressable
                    accessibilityLabel="Connect with token or guest access"
                    accessibilityRole="button"
                    disabled={!serviceUrl.trim() || connecting}
                    onPress={connect}
                    style={({ pressed }) => [
                      styles.button,
                      { backgroundColor: palette.accent },
                      (!serviceUrl.trim() || connecting) &&
                        styles.buttonDisabled,
                      pressed && styles.buttonPressed,
                    ]}
                  >
                    {connecting ? (
                      <ActivityIndicator color="#ffffff" size="small" />
                    ) : (
                      <Text style={styles.buttonText}>
                        Connect with token or guest access
                      </Text>
                    )}
                  </Pressable>
                </View>
              </View>
            )}
          </>
        )}
      </View>
    </View>
  );
}

function message(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}

const lightPalette = {
  background: '#ffffff',
  sidebar: '#f5f5f5',
  separator: '#dddddd',
  selection: '#e7e7e7',
  text: '#171717',
  secondaryText: '#666666',
  accent: '#2563eb',
};

const darkPalette = {
  background: '#1e1e1e',
  sidebar: '#262626',
  separator: '#3a3a3a',
  selection: '#383838',
  text: '#f4f4f4',
  secondaryText: '#a3a3a3',
  accent: '#3b82f6',
};

const styles = StyleSheet.create({
  window: {
    flex: 1,
    flexDirection: 'row',
    minHeight: 480,
  },
  sidebar: {
    width: 220,
    borderRightWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 14,
    paddingTop: 20,
  },
  appName: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 24,
    paddingHorizontal: 8,
  },
  navigation: {
    gap: 4,
  },
  navigationItem: {
    borderRadius: 7,
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  navigationText: {
    fontSize: 14,
    fontWeight: '500',
  },
  content: {
    flex: 1,
    padding: 32,
  },
  heading: {
    fontSize: 28,
    fontWeight: '600',
  },
  work: {
    flex: 1,
    marginTop: 24,
  },
  accountBar: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    marginBottom: 4,
    paddingBottom: 14,
  },
  accountName: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 2,
  },
  accountIdentity: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 12,
  },
  textButton: {
    paddingVertical: 4,
  },
  issueRow: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    minHeight: ISSUE_ROW_HEIGHT,
    paddingHorizontal: 4,
  },
  issueMarker: {
    fontSize: 17,
    marginRight: 10,
  },
  issueId: {
    fontSize: 12,
    marginRight: 12,
    width: 82,
  },
  issueSummary: {
    flex: 1,
    fontSize: 14,
  },
  emptyList: {
    alignItems: 'center',
    flexGrow: 1,
    justifyContent: 'center',
  },
  connectionState: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
    paddingBottom: 48,
  },
  connectionTitle: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 8,
  },
  connectionDescription: {
    fontSize: 14,
    marginBottom: 20,
    maxWidth: 420,
    textAlign: 'center',
  },
  form: {
    gap: 10,
    width: 360,
  },
  savedAccounts: {
    gap: 8,
    marginBottom: 4,
  },
  savedAccountsTitle: {
    fontSize: 12,
    fontWeight: '600',
  },
  savedAccountRow: {
    alignItems: 'center',
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
  },
  savedAccountButton: {
    flex: 1,
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  forgetButton: {
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  authDivider: {
    fontSize: 12,
    textAlign: 'center',
  },
  input: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    fontSize: 14,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  errorText: {
    color: '#d93025',
    fontSize: 13,
  },
  button: {
    alignItems: 'center',
    borderRadius: 8,
    minHeight: 36,
    justifyContent: 'center',
    paddingHorizontal: 18,
    paddingVertical: 9,
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  buttonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
});

export default App;
