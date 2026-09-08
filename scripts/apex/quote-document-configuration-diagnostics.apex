QuoteDocumentConfigurationDiagnostics.Report report = QuoteDocumentConfigurationDiagnostics.inspect();
System.debug(LoggingLevel.ERROR, 'QDTD_CONFIGURATION_DIAGNOSTICS ' + JSON.serializePretty(report));
