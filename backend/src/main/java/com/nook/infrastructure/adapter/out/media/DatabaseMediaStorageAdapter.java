package com.nook.infrastructure.adapter.out.media;

import com.nook.application.port.out.MediaStoragePort;
import com.nook.domain.SocialEntities.MediaObject;
import com.nook.exception.ApiException;
import jakarta.persistence.EntityManager;
import java.io.IOException;
import java.io.InputStream;
import java.util.UUID;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
@Profile("prod")
public class DatabaseMediaStorageAdapter implements MediaStoragePort {
  private final EntityManager entityManager;

  public DatabaseMediaStorageAdapter(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  @Override public StoredMedia storeUserPhoto(UUID id, InputStream input, String contentType) {
    String extension = switch (contentType) {
      case "image/png" -> "png";
      case "image/heic" -> "heic";
      case "image/heif" -> "heif";
      default -> "jpg";
    };
    String filename = id + "." + extension;
    try {
      MediaObject value = new MediaObject();
      value.filename = filename;
      value.contentType = contentType;
      value.content = input.readAllBytes();
      entityManager.persist(value);
      return new StoredMedia("/api/v1/media/photos/" + filename, filename);
    } catch (IOException error) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PHOTO", "No se pudo leer la foto");
    }
  }

  @Override public StoredContent resolveUserPhoto(String filename) {
    MediaObject value = entityManager.createQuery(
            "select m from SocialEntities$MediaObject m where m.filename=:filename", MediaObject.class)
        .setParameter("filename", filename).getResultStream().findFirst()
        .orElseThrow(() -> new ApiException(
            HttpStatus.NOT_FOUND, "PHOTO_NOT_FOUND", "Foto no encontrada"));
    return new StoredContent(value.content, value.contentType);
  }

  @Override public void deleteUserPhoto(String publicUrl) {
    if (publicUrl == null || !publicUrl.startsWith("/api/v1/media/photos/")) return;
    String filename = publicUrl.substring(publicUrl.lastIndexOf('/') + 1);
    entityManager.createQuery("delete from SocialEntities$MediaObject m where m.filename=:filename")
        .setParameter("filename", filename).executeUpdate();
  }
}
