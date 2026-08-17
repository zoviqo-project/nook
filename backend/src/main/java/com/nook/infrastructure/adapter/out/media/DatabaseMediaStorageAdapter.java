package com.nook.infrastructure.adapter.out.media;

import com.nook.application.port.out.MediaStoragePort;
import com.nook.exception.ApiException;
import java.io.IOException;
import java.io.InputStream;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
@Profile("prod & !object-storage")
public class DatabaseMediaStorageAdapter implements MediaStoragePort {
  private final JdbcTemplate jdbc;

  public DatabaseMediaStorageAdapter(JdbcTemplate jdbc) {
    this.jdbc = jdbc;
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
      jdbc.update("insert into media_objects(id,filename,content_type,content,created_at) values(?,?,?,?,?)",
          id, filename, contentType, input.readAllBytes(), Timestamp.from(Instant.now()));
      return new StoredMedia("/api/v1/media/photos/" + filename, filename);
    } catch (IOException error) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PHOTO", "No se pudo leer la foto");
    }
  }

  @Override public StoredContent resolveUserPhoto(String filename) {
    try {
      return jdbc.queryForObject("select content,content_type from media_objects where filename=?",
          (result, row) -> new StoredContent(
              result.getBytes("content"), result.getString("content_type")), filename);
    } catch (EmptyResultDataAccessException error) {
      throw new ApiException(HttpStatus.NOT_FOUND, "PHOTO_NOT_FOUND", "Foto no encontrada");
    }
  }

  @Override public void deleteUserPhoto(String publicUrl) {
    if (publicUrl == null || !publicUrl.startsWith("/api/v1/media/photos/")) return;
    String filename = publicUrl.substring(publicUrl.lastIndexOf('/') + 1);
    jdbc.update("delete from media_objects where filename=?", filename);
  }
}
