package com.nook.service;

import com.nook.domain.SocialEntities.IntentCategory;
import com.nook.domain.SocialEntities.IntentSubcategory;
import com.nook.domain.SocialEntities.UserIntent;
import com.nook.dto.ApiDtos.*;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class IntentService {
  private final SocialRepository repository;
  private final SocialMapper mapper;
  private final AuditService audit;

  public IntentService(SocialRepository repository, SocialMapper mapper, AuditService audit) {
    this.repository = repository;
    this.mapper = mapper;
    this.audit = audit;
  }

  public List<IntentCategoryDto> categories() {
    return repository.intentCategories().stream().map(category -> new IntentCategoryDto(
        category.id, category.code, category.name, category.icon, category.displayOrder,
        repository.intentSubcategories(category.id).stream().map(item ->
            new IntentSubcategoryDto(item.id, item.code, item.name, item.displayOrder)).toList()
    )).toList();
  }

  public UserIntentState current(UUID userId) {
    return new UserIntentState(mapper.intent(userId));
  }

  @Transactional
  public UserIntentState update(UUID userId, UpdateUserIntent request) {
    IntentCategory category = repository.intentCategory(request.categoryId());
    IntentSubcategory subcategory = repository.intentSubcategory(request.subcategoryId());
    if (category == null || !category.active || subcategory == null || !subcategory.active) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_INTENT", "La intención seleccionada ya no está disponible");
    }
    if (!subcategory.categoryId.equals(category.id)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_INTENT_PAIR", "La opción no pertenece a esa categoría");
    }
    UserIntent value = repository.userIntent(userId);
    Instant now = Instant.now();
    if (value == null) {
      value = new UserIntent();
      value.userId = userId;
      value.createdAt = now;
      repository.save(value);
    }
    value.categoryId = category.id;
    value.subcategoryId = subcategory.id;
    value.updatedAt = now;
    audit.record(userId, "INTENT_UPDATED", "USER", userId);
    return new UserIntentState(new UserIntentDto(category.id, category.code, category.name,
        category.icon, subcategory.id, subcategory.code, subcategory.name));
  }
}
