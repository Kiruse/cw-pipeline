import { restful, RestApi, RestMethods } from '@kiruse/restful';
import { extendDefaultMarshaller, IgnoreMarshalUnit, MarshalUnitContext, morph, pass, RecaseMarshalUnit } from '@kiruse/marshal';
import { camelCase } from 'case-anything';

type DrandApi = RestApi<{
  [chainHash: string]: {
    info: RestMethods<{
      get(): DrandChainInfo;
    }>;

    public: {
      latest: RestMethods<{
        get(): DrandRound;
      }>;
    } & {
      [round: number]: RestMethods<{
        get(): DrandRound;
      }>;
    };
  };
} & {
  chains: RestMethods<{
    get(): string[];
  }>;
}>;

export interface DrandChainInfo {
  /** Static network public key. This key should be published to the blockchain for randomness
   * verification using the scheme identified by `schemeID`.
   */
  publicKey: string;
  /** Randomness period in seconds. */
  period: number;
  /** Genesis timestamp. Note that the API returns the timestamp in seconds which this interface converts to a `Date`. */
  genesisTime: Date;
  /** Chain hash hex string. */
  hash: string;
  /** Group hash hex string. */
  groupHash: string;
  /** Long signature scheme identifier. */
  schemeID: string;
  /** Metadata about the chain. */
  metadata: {
    /** Short beacon identifier. */
    beaconID: string;
  };
}

export interface DrandRound {
  /** Round number. */
  round: number;
  /** Randomness value as fixed-length hex string. */
  randomness: string;
  /** Signature of the current round. Verifiable by using the chain's public key as returned by the `/[chain-hash]/info` endpoint. */
  signature: string;
  /** Signature of the previous round. */
  previousSignature: string;
}

const { marshal, unmarshal } = extendDefaultMarshaller([
  IgnoreMarshalUnit(Date),
  RecaseMarshalUnit(
    s => s,
    camelCase,
  ),
  {
    generic: false,
    marshal: () => pass,
    unmarshal(value: any, ctx: MarshalUnitContext) {
      if (!value || typeof value !== 'object' || typeof value.genesis_time !== 'number')
        return pass;
      const result = {
        ...value,
        genesis_time: new Date(value.genesis_time * 1000),
      };
      return morph(ctx.unmarshal(result));
    },
  },
]);

export const drand = (baseUrl: string) => restful.default<DrandApi>({
  baseUrl,
  marshal,
  unmarshal,
});
