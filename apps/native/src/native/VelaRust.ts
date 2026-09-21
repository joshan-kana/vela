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

type VelaRustModule = {
  loadMyWork(
    serviceUrl: string,
    bearerToken: string,
    top: number,
  ): Promise<MyWork>;
};

export async function loadMyWork(
  serviceUrl: string,
  bearerToken: string,
  top = 50,
): Promise<MyWork> {
  const module = NativeModules.VelaRust as VelaRustModule | undefined;

  if (!module) {
    throw new Error('Vela Rust bridge is unavailable');
  }

  return module.loadMyWork(serviceUrl, bearerToken, top);
}
