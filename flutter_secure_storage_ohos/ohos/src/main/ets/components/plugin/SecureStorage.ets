import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { huks } from '@kit.UniversalKeystoreKit';

const KEY_ALIAS = 'flutter_secure_storage_ohos_aes_gcm_v1';
const PREFERENCES_NAME = 'FlutterSecureStorage';
const ENTRY_PREFIX = 'fss_ohos_v1_';
const FORMAT_VERSION = 'v1';
const NONCE_LENGTH = 12;
const TAG_LENGTH = 16;

export default class SecureStorage {
  private readonly data: preferences.Preferences;
  private readonly base64 = new util.Base64Helper();
  private readonly encoder = new util.TextEncoder('utf-8');
  private readonly decoder = util.TextDecoder.create('utf-8');
  private keyReady: Promise<void> | null = null;

  constructor(context: Context) {
    this.data = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
  }

  async write(key: string, value: string): Promise<void> {
    await this.ensureKey();
    const nonce = cryptoFramework.createRandom().generateRandomSync(NONCE_LENGTH).data;
    const ciphertext = await this.crypt(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT,
      nonce,
      this.encoder.encodeInto(value),
    );
    const stored = `${FORMAT_VERSION}:${this.base64.encodeToStringSync(nonce)}:${this.base64.encodeToStringSync(ciphertext)}`;
    this.data.putSync(this.entryKey(key), stored);
    await this.data.flush();
  }

  async read(key: string): Promise<string | null> {
    const entry = this.entryKey(key);
    if (!this.data.hasSync(entry)) {
      return null;
    }
    const stored = this.data.getSync(entry, '');
    if (typeof stored !== 'string') {
      throw new Error('Invalid stored value');
    }
    const parts = stored.split(':');
    if (parts.length !== 3 || parts[0] !== FORMAT_VERSION) {
      throw new Error('Unsupported stored value format');
    }
    const nonce = this.base64.decodeSync(parts[1]);
    const ciphertext = this.base64.decodeSync(parts[2]);
    if (nonce.length !== NONCE_LENGTH || ciphertext.length < TAG_LENGTH) {
      throw new Error('Invalid ciphertext');
    }
    if (!(await huks.isKeyItemExist(KEY_ALIAS, { properties: [] }))) {
      throw new Error('Encryption key is unavailable');
    }
    const plaintext = await this.crypt(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      nonce,
      ciphertext.slice(0, ciphertext.length - TAG_LENGTH),
      ciphertext.slice(ciphertext.length - TAG_LENGTH),
    );
    return this.decoder.decodeWithStream(plaintext);
  }

  containsKey(key: string): boolean {
    return this.data.hasSync(this.entryKey(key));
  }

  async delete(key: string): Promise<void> {
    this.data.deleteSync(this.entryKey(key));
    await this.data.flush();
  }

  async readAll(): Promise<Map<string, string>> {
    const result = new Map<string, string>();
    for (const entry of Object.keys(this.data.getAllSync())) {
      if (entry.startsWith(ENTRY_PREFIX)) {
        const value = await this.read(entry.substring(ENTRY_PREFIX.length));
        if (value !== null) {
          result.set(entry.substring(ENTRY_PREFIX.length), value);
        }
      }
    }
    return result;
  }

  async deleteAll(): Promise<void> {
    for (const entry of Object.keys(this.data.getAllSync())) {
      if (entry.startsWith(ENTRY_PREFIX)) {
        this.data.deleteSync(entry);
      }
    }
    await this.data.flush();
  }

  private entryKey(key: string): string {
    return ENTRY_PREFIX + key;
  }

  private ensureKey(): Promise<void> {
    if (this.keyReady === null) {
      this.keyReady = this.createKey().catch((error: Error): Promise<void> => {
        this.keyReady = null;
        return Promise.reject(error);
      });
    }
    return this.keyReady;
  }

  private async createKey(): Promise<void> {
    if (await huks.isKeyItemExist(KEY_ALIAS, { properties: [] })) {
      return;
    }
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      },
    ];
    await huks.generateKeyItem(KEY_ALIAS, { properties });
  }

  private async crypt(
    purpose: huks.HuksKeyPurpose,
    nonce: Uint8Array,
    input: Uint8Array,
    tag?: Uint8Array,
  ): Promise<Uint8Array> {
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
    ];
    if (tag !== undefined) {
      properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag });
    }

    const options: huks.HuksOptions = { properties, inData: input };
    const session = await huks.initSession(KEY_ALIAS, options);
    let finished = false;
    try {
      const final = await huks.finishSession(session.handle, options);
      finished = true;
      return final.outData ?? new Uint8Array();
    } finally {
      if (!finished) {
        await huks.abortSession(session.handle, { properties: [] }).catch((): void => {});
      }
    }
  }
}
