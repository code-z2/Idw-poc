library pks_4337_sdk;

import 'package:pks_4337_sdk/pks_4337_sdk.dart';

export 'hd_key.dart';
export 'passkey.dart';

class Signer {
  final PasskeysInterface? passkey;
  final HDkeysInterface? hdkey;

  SignerType defaultSigner;

  Signer({this.passkey, this.hdkey, SignerType signer = SignerType.hdkeys})
      : assert(passkey != null || hdkey != null),
        defaultSigner = signer;

  Future<T> sign<T>(dynamic hash, {int? index, String? id}) async {
    switch (defaultSigner) {
      case SignerType.passkeys:
        require(
            id != null && id.isNotEmpty, "Passkey Credential ID is required");
        return await passkey!.sign(hash, id!) as T;
      default:
        return await hdkey!.sign(hash, index: index, id: id) as T;
    }
  }
}

enum SignerType {
  passkeys,
  hdkeys,
}
