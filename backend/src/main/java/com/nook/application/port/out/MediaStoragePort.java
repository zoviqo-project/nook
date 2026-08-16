package com.nook.application.port.out;

import java.io.InputStream;
import java.nio.file.Path;
import java.util.UUID;

public interface MediaStoragePort {
  StoredMedia storeUserPhoto(UUID photoId, InputStream input, String contentType);
  Path resolveUserPhoto(String filename);
  void deleteUserPhoto(String publicUrl);

  record StoredMedia(String publicUrl, String filename) {}
}
