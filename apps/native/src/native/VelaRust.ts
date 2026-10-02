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

type BridgeResponse =
  | {
      status: 'ok';
      data: MyWork;
    }
  | {
      status: 'error';
      message: string;
    };

type VelaRustModule = {
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

export async function loadMyWork(
  serviceUrl: string,
  bearerToken: string,
  top = 50,
): Promise<MyWork> {
  const module = NativeModules.VelaRust as VelaRustModule | undefined;

  if (!module) {
    throw new Error('Vela Rust bridge is unavailable');
  }

  if (module.loadMyWork) {
    return module.loadMyWork(serviceUrl, bearerToken, top);
  }

  if (module.loadMyWorkJson) {
    const response = JSON.parse(
      await module.loadMyWorkJson(serviceUrl, bearerToken, top),
    ) as BridgeResponse;

    if (response.status === 'ok') {
      return response.data;
    }

    throw new Error(response.message);
  }

  throw new Error('Vela Rust bridge has no supported My Work method');
}
