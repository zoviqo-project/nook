package com.nook;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.nook.domain.SocialEntities.*;
import com.nook.dto.ApiDtos.UpdateUserIntent;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import com.nook.service.AuditService;
import com.nook.service.IntentService;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class IntentServiceTest {
  private final SocialRepository repository = mock(SocialRepository.class);
  private final SocialMapper mapper = mock(SocialMapper.class);
  private final IntentService service = new IntentService(
      repository, mapper, new AuditService(repository));

  @Test void savesAValidCategoryAndSubcategoryPair() {
    UUID user = UUID.randomUUID();
    IntentCategory category = new IntentCategory(); category.id = UUID.randomUUID();
    category.code = "PROJECT"; category.name = "Proyecto"; category.icon = "laptopcomputer";
    IntentSubcategory subcategory = new IntentSubcategory(); subcategory.id = UUID.randomUUID();
    subcategory.categoryId = category.id; subcategory.code = "MOBILE_APP"; subcategory.name = "App móvil";
    when(repository.intentCategory(category.id)).thenReturn(category);
    when(repository.intentSubcategory(subcategory.id)).thenReturn(subcategory);

    var result = service.update(user, new UpdateUserIntent(category.id, subcategory.id));

    assertThat(result.intent().categoryCode()).isEqualTo("PROJECT");
    assertThat(result.intent().subcategoryCode()).isEqualTo("MOBILE_APP");
    verify(repository).save(argThat(value -> value instanceof UserIntent intent
        && intent.userId.equals(user) && intent.categoryId.equals(category.id)
        && intent.subcategoryId.equals(subcategory.id)));
  }

  @Test void rejectsASubcategoryFromAnotherCategory() {
    IntentCategory category = new IntentCategory(); category.id = UUID.randomUUID();
    IntentSubcategory subcategory = new IntentSubcategory(); subcategory.id = UUID.randomUUID();
    subcategory.categoryId = UUID.randomUUID();
    when(repository.intentCategory(category.id)).thenReturn(category);
    when(repository.intentSubcategory(subcategory.id)).thenReturn(subcategory);

    assertThatThrownBy(() -> service.update(UUID.randomUUID(),
        new UpdateUserIntent(category.id, subcategory.id))).isInstanceOf(ApiException.class);
  }
}
