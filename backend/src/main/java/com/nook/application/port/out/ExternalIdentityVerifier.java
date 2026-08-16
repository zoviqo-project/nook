package com.nook.application.port.out;

import com.nook.domain.SocialEntities.AuthProvider;

public interface ExternalIdentityVerifier {
  VerifiedIdentity verify(AuthProvider provider, String identityToken);

  record VerifiedIdentity(String subject, String email, boolean emailVerified, String displayName) {}
}
