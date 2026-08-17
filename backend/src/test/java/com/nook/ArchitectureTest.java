package com.nook;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.core.importer.ClassFileImporter;
import org.junit.jupiter.api.Test;

class ArchitectureTest {
  private final com.tngtech.archunit.core.domain.JavaClasses classes =
      new ClassFileImporter().importPackages("com.nook");

  @Test void controllersDoNotAccessPersistenceDirectly() {
    noClasses().that().resideInAPackage("..controller..")
        .should().dependOnClassesThat().resideInAnyPackage(
            "..repository..", "..persistence..", "..infrastructure.adapter.out..")
        .check(classes);
  }

  @Test void outputPortsRemainFrameworkIndependent() {
    noClasses().that().resideInAPackage("..application.port.out..")
        .should().dependOnClassesThat().resideInAnyPackage("org.springframework..", "jakarta.persistence..")
        .check(classes);
  }

  @Test void lowerLayersNeverDependOnRestControllers() {
    noClasses().that().resideInAnyPackage("..domain..", "..application..", "..service..")
        .should().dependOnClassesThat().resideInAPackage("..controller..")
        .check(classes);
  }

  @Test void useCasesDoNotDependOnOutboundAdapters() {
    noClasses().that().resideInAnyPackage("..service..", "..application..")
        .should().dependOnClassesThat().resideInAPackage("..infrastructure.adapter.out..")
        .check(classes);
  }
}
