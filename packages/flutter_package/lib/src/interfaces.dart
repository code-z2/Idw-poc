import 'dart:typed_data';

import 'package:pks_4337_sdk/src/signer/passkey_types.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

abstract class FactoryInterface {
  Future<String> createAccount(
    Uint8List credentialHex,
    BigInt salt, {
    required Credentials credentials,
    Transaction? transaction,
  });
  Future<String> createPasskeyAccount(
    Uint8List credentialHex,
    BigInt x,
    BigInt y,
    BigInt salt, {
    required Credentials credentials,
    Transaction? transaction,
  });
  Future<EthereumAddress> getAddress(
    EthereumAddress owner,
    BigInt salt, {
    BlockNum? atBlock,
  });
  Future<EthereumAddress> getPasskeyAccountAddress(
    Uint8List credentialHex,
    BigInt x,
    BigInt y,
    BigInt salt, {
    BlockNum? atBlock,
  });
}

abstract class HDkeysInterface {
  Future<String> getAddress(int index, {String? id});
  Future<Uint8List> sign(Uint8List hash, {int? index, String? id});
  Future<MsgSignature> signToEc(Uint8List hash, {int? index, String? id});
}

abstract class PasskeysInterface {
  Future<PassKeySignature> sign(String hash, String credentialId);
}
