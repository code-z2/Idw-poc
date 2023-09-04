import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:webauthn/webauthn.dart';
// ignore: depend_on_referenced_packages
import 'package:cbor/cbor.dart';
import 'common.dart';

class PasskeyUtils {
  final PassKeysOptions _opts;
  final Authenticator _auth;

  PasskeyUtils(String namespace, String name, String origin,
      {bool? crossOrigin})
      : _opts = PassKeysOptions(
          namespace: namespace,
          name: name,
          origin: origin,
          crossOrigin: crossOrigin ?? false,
        ),
        _auth = Authenticator(true, true);

  static const _makeCredentialJson = '''{
    "authenticatorExtensions": "",
    "clientDataHash": "",
    "credTypesAndPubKeyAlgs": [
        ["public-key", -7]
    ],
    "excludeCredentials": [],
    "requireResidentKey": true,
    "requireUserPresence": true,
    "requireUserVerification": false,
    "rp": {
        "name": "",
        "id": ""
    },
    "user": {
        "name": "",
        "displayName": "",
        "id": ""
    }
  }''';

  static const getAssertionJson = '''{
    "allowCredentialDescriptorList": [],
    "authenticatorExtensions": "",
    "clientDataHash": "",
    "requireUserPresence": true,
    "requireUserVerification": false,
    "rpId": ""
  }''';

  

  ///The [getMessagingSignature] function takes in the [authResponseSignature] from passkeys auth
  ///It uses the [ASN1Parser] to parse the signature decoded from base64
  ///and checks for objects in the List using the [nextObject] stream from the [ASN1Parser]
  ///we then check for the elements by index
  ///Remove leading zeros using [shouldRemoveLeadingZero]
  ///and convert to hex using [hexlify]
  ///and return [r] and [s]

  

  ///Creates random values with [Uuid] to generate the challenge
  String _randomChallenge(PassKeysOptions options) {
    final uuid = const Uuid()
        .v5buffer(Uuid.NAMESPACE_URL, options.name, List<int>.filled(32, 0));
    return base64Url.encode(uuid);
  }

  ///Creates the [clientDataHash]
  Uint8List clientDataHash(PassKeysOptions options, {String? challenge}) {
    options.challenge = challenge ?? _randomChallenge(options);
    final clientDataJson = jsonEncode({
      "type": options.type,
      "challenge": options.challenge,
      "origin": options.origin,
      "crossOrigin": options.crossOrigin
    });
    return Uint8List.fromList(utf8.encode(clientDataJson));
  }

  Uint8List clientDataHash32(PassKeysOptions options, {String? challenge}) {
    final dataBuffer = clientDataHash(options, challenge: challenge);
    final sha256Hash = sha256.convert(dataBuffer);
    return Uint8List.fromList(sha256Hash.bytes);
  }

  /// Decodes the raw authentication data to extract relevant authentication details.
  ///
  /// Parameters:
  /// - `authData`: Raw authentication data received from the authentication process.
  ///
  /// Returns:
  /// An AuthData object containing decoded authentication details.
  AuthData _decode(dynamic authData) {
    // Extract the length of the public key from the authentication data.
    final l = (authData[53] << 8) + authData[54];

    // Calculate the offset for the start of the public key data.
    final publicKeyOffset = 55 + l;

    // Extract the public key data from the authentication data.
    final pKey = authData.sublist(publicKeyOffset);

    // Extract the credential ID from the authentication data.
    final credentialId = authData.sublist(55, publicKeyOffset);

    // Extract and encode the aaGUID from the authentication data.
    final aaGUID = base64Url.encode(authData.sublist(37, 53));

    // Decode the CBOR-encoded public key and convert it to a map.
    final decodedPubKey = cbor.decode(pKey).toObject() as Map;

// Calculate the hash of the credential ID.
    final credentialHash = hexlify(keccak256(Uint8List.fromList(credentialId)));
// Extract x and y coordinates from the decoded public key.
    final x = hexlify(decodedPubKey[-2]);
    final y = hexlify(decodedPubKey[-3]);

    return AuthData(
        credentialHash, base64Url.encode(credentialId), [x, y], aaGUID);
  }

  AuthData _decodeAttestation(Attestation attestation) {
    final attestationAsCbor = attestation.asCBOR();
    final decodedAttestationAsCbor =
        cbor.decode(attestationAsCbor).toObject() as Map;
    final authData = decodedAttestationAsCbor["authData"];
    return _decode(authData);
  }

  ///The register function registers a username and returns an [Attestation].
  ///
  ///The [Authenticator] allows  biometric authentication.
  ///
  ///@See https://pub.dev/packages/webauthn
  Future<Attestation> _register(
      String name, bool requiresUserVerification) async {
    final options = _opts;
    options.type = "webauthn.create";
    final hash = clientDataHash32(options);
    final entity =
        MakeCredentialOptions.fromJson(jsonDecode(_makeCredentialJson));
    entity.userEntity = UserEntity(
      id: Uint8List.fromList(utf8.encode(name)),
      displayName: name,
      name: name,
    );
    entity.clientDataHash = hash;
    entity.rpEntity.id = options.namespace;
    entity.rpEntity.name = options.name;
    entity.requireUserVerification = requiresUserVerification;
    entity.requireUserPresence = !requiresUserVerification;
    return await _auth.makeCredential(entity);
  }

  ///The [_authenticate] function authenticates a user and returns an [Assertion].
  ///Parameters:
  ///- `credentialIds`: List of credential IDs to be used for authentication.
  Future<Assertion> _authenticate(List<String> credentialIds,
      Uint8List challenge, bool requiresUserVerification) async {
    final entity = GetAssertionOptions.fromJson(jsonDecode(getAssertionJson));
    entity.allowCredentialDescriptorList = credentialIds
        .map((credentialId) => PublicKeyCredentialDescriptor(
            type: PublicKeyCredentialType.publicKey,
            id: base64Url.decode(credentialId)))
        .toList();
    if (entity.allowCredentialDescriptorList!.isEmpty) {
      throw AuthenticatorException('User not found');
    }
    entity.clientDataHash = challenge;
    entity.rpId = _opts.namespace;
    entity.requireUserVerification = requiresUserVerification;
    entity.requireUserPresence = !requiresUserVerification;
    return await _auth.getAssertion(entity);
  }

  /// Call the [register] function in your flutter app
  /// to register a user and return a [PassKeyPair] key pair
  Future<PassKeyPair> register(
      String name, bool requiresUserVerification) async {
    final attestation = await _register(name, requiresUserVerification);
    final authData = _decodeAttestation(attestation);
    if (authData.publicKey.length != 2) {
      throw "Invalid public key";
    }
    return PassKeyPair(
      authData.credentialHash,
      authData.credentialId,
      authData.publicKey[0],
      authData.publicKey[1],
      name,
      authData.aaGUID,
      DateTime.now(),
    );
  }

  Future<PassKeySignature> signMessage(String hash, String credentialId) async {
    final options = _opts;
    options.type = "webauthn.get";
    final hash32 = hash.length == 64 ? hash : hash.substring(2);
    final hashBase64 = base64Url
        .encode(hexToArrayBuffer(hash32))
        .replaceAll(RegExp(r'=', multiLine: true, caseSensitive: false), '');
    final challenge32 = clientDataHash32(options, challenge: hashBase64);
    final assertion = await _authenticate([credentialId], challenge32, true);
    final sig = await getMessagingSignature(assertion.signature);
    final challenge = clientDataHash(options, challenge: hashBase64);
    final clientDataJSON = utf8.decode(challenge);
    int challengePos = clientDataJSON.indexOf(hashBase64);
    String challengePrefix = clientDataJSON.substring(0, challengePos);
    String challengeSuffix =
        clientDataJSON.substring(challengePos + hashBase64.length);
    return PassKeySignature(
      base64Url.encode(assertion.selectedCredentialId),
      sig[0],
      sig[1],
      assertion.authenticatorData,
      challengePrefix,
      challengeSuffix,
    );
  }
}

class PassKeysOptions {
  final String namespace;
  final String name;
  final String origin;
  bool? crossOrigin;
  String? challenge;
  String? type;
  PassKeysOptions(
      {required this.namespace,
      required this.name,
      required this.origin,
      this.crossOrigin,
      this.challenge,
      this.type});
}

class AuthData {
  final String credentialHash;
  final String credentialId;
  final List<String> publicKey;
  final String aaGUID;
  AuthData(this.credentialHash, this.credentialId, this.publicKey, this.aaGUID);
}

class PassKeyPair {
  final String credentialHash;
  final String? pubKeyX;
  final String? pubKeyY;
  final String credentialId;
  final String name;
  final String aaGUID;
  final DateTime registrationTime;
  PassKeyPair(this.credentialHash, this.credentialId, this.pubKeyX,
      this.pubKeyY, this.name, this.aaGUID, this.registrationTime);
}

class PassKeySignature {
  final String credentialId;
  final String r;
  final String s;
  final Uint8List authData;
  final String clientDataPrefix;
  final String clientDataSuffix;
  PassKeySignature(this.credentialId, this.r, this.s, this.authData,
      this.clientDataPrefix, this.clientDataSuffix);
}