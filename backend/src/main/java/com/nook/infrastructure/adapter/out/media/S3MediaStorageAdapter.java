package com.nook.infrastructure.adapter.out.media;

import com.nook.application.port.out.MediaStoragePort;
import com.nook.exception.ApiException;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

@Component
@Profile("object-storage")
public class S3MediaStorageAdapter implements MediaStoragePort {
  private static final String PREFIX = "user-photos/";
  private final S3Client s3;
  private final String bucket;
  private final String publicBaseUrl;

  public S3MediaStorageAdapter(
      @Value("${nook.object-storage.bucket}") String bucket,
      @Value("${nook.object-storage.region}") String region,
      @Value("${nook.object-storage.access-key}") String accessKey,
      @Value("${nook.object-storage.secret-key}") String secretKey,
      @Value("${nook.object-storage.public-base-url}") String publicBaseUrl,
      @Value("${nook.object-storage.endpoint:}") String endpoint) {
    this.bucket = required(bucket, "OBJECT_STORAGE_BUCKET");
    this.publicBaseUrl = stripTrailingSlash(required(publicBaseUrl, "OBJECT_STORAGE_PUBLIC_BASE_URL"));
    var builder = S3Client.builder()
        .region(Region.of(required(region, "OBJECT_STORAGE_REGION")))
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(
            required(accessKey, "OBJECT_STORAGE_ACCESS_KEY"), required(secretKey, "OBJECT_STORAGE_SECRET_KEY"))))
        .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(!endpoint.isBlank()).build());
    if (!endpoint.isBlank()) builder.endpointOverride(URI.create(endpoint));
    this.s3 = builder.build();
  }

  @Override
  public StoredMedia storeUserPhoto(UUID id, InputStream input, String contentType) {
    String filename = id + extension(contentType);
    String key = PREFIX + filename;
    try {
      byte[] bytes = input.readAllBytes();
      s3.putObject(request -> request.bucket(bucket).key(key).contentType(contentType)
          .cacheControl("public, max-age=31536000, immutable"), RequestBody.fromBytes(bytes));
      return new StoredMedia(publicBaseUrl + "/" + key, filename);
    } catch (IOException | RuntimeException error) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "PHOTO_STORAGE_ERROR", "No se pudo guardar la foto");
    }
  }

  @Override
  public StoredContent resolveUserPhoto(String filename) {
    try {
      ResponseBytes<GetObjectResponse> object = s3.getObjectAsBytes(request -> request.bucket(bucket).key(PREFIX + filename));
      String contentType = object.response().contentType();
      return new StoredContent(object.asByteArray(), contentType == null ? "image/jpeg" : contentType);
    } catch (NoSuchKeyException error) {
      throw new ApiException(HttpStatus.NOT_FOUND, "PHOTO_NOT_FOUND", "Foto no encontrada");
    } catch (RuntimeException error) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "PHOTO_STORAGE_ERROR", "No se pudo cargar la foto");
    }
  }

  @Override
  public void deleteUserPhoto(String publicUrl) {
    String prefix = publicBaseUrl + "/" + PREFIX;
    if (publicUrl == null || !publicUrl.startsWith(prefix)) return;
    String filename = publicUrl.substring(prefix.length());
    if (filename.isBlank() || filename.contains("/")) return;
    try { s3.deleteObject(request -> request.bucket(bucket).key(PREFIX + filename)); }
    catch (RuntimeException ignored) { }
  }

  private static String extension(String contentType) {
    return switch (contentType) {
      case "image/png" -> ".png";
      case "image/heic" -> ".heic";
      case "image/heif" -> ".heif";
      default -> ".jpg";
    };
  }
  private static String required(String value, String variable) {
    if (value == null || value.isBlank()) throw new IllegalStateException(variable + " es obligatorio");
    return value;
  }
  private static String stripTrailingSlash(String value) {
    return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
  }
}
