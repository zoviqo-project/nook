package com.nook.infrastructure.adapter.out.media;

import com.nook.application.port.out.MediaStoragePort;
import com.nook.exception.ApiException;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.*;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class LocalMediaStorageAdapter implements MediaStoragePort {
  private final Path root;

  public LocalMediaStorageAdapter(@Value("${nook.photo-storage:./data/photos}") String storage) {
    root = Paths.get(storage).toAbsolutePath().normalize();
  }

  @Override public StoredMedia storeUserPhoto(UUID id,InputStream input,String contentType) {
    String extension=switch(contentType){case "image/png"->"png";case "image/heic"->"heic";default->"jpg";};
    String filename=id+"."+extension;
    try {
      Files.createDirectories(root);
      Files.copy(input,root.resolve(filename),StandardCopyOption.REPLACE_EXISTING);
      return new StoredMedia("/api/v1/media/photos/"+filename,filename);
    } catch(IOException error) {
      throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR,"PHOTO_STORAGE_ERROR","No se pudo guardar la foto");
    }
  }

  @Override public Path resolveUserPhoto(String filename) {
    Path candidate=root.resolve(filename).normalize();
    if(!candidate.startsWith(root)||!Files.isRegularFile(candidate))
      throw new ApiException(HttpStatus.NOT_FOUND,"PHOTO_NOT_FOUND","Foto no encontrada");
    return candidate;
  }

  @Override public void deleteUserPhoto(String publicUrl) {
    if(publicUrl==null||!publicUrl.startsWith("/api/v1/media/photos/"))return;
    String filename=publicUrl.substring(publicUrl.lastIndexOf('/')+1);
    try { Files.deleteIfExists(resolveUserPhoto(filename)); }
    catch(ApiException ignored) { }
    catch(IOException ignored) { }
  }
}
