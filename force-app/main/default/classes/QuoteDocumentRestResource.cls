/**
 * Read-only, identity-bound REST entry point for document renderers.
 *
 * The endpoint accepts only the request Id and fingerprint returned by the
 * generation launch. It never offers a Quote-Id-only shortcut. Domain errors
 * are reduced to stable codes and safe messages so record identifiers,
 * fingerprints, payload hashes, and customer values are not reflected in an
 * HTTP response.
 */
@RestResource(urlMapping='/quote-document-totals/v2/quotes/*')
@SuppressWarnings('PMD.CyclomaticComplexity')
global with sharing class QuoteDocumentRestResource {
  private static final String REQUEST_HEADER = 'X-QDTD-Request-Id';
  private static final String FINGERPRINT_HEADER = 'X-QDTD-Fingerprint';

  /** Writes the validated payload or a sanitized error envelope to RestContext. */
  @HttpGet
  global static void retrieve() {
    RestResponse response = RestContext.response;
    response.addHeader('Cache-Control', 'no-store');
    response.addHeader('Content-Type', 'application/json; charset=UTF-8');

    try {
      Id quoteId = quoteIdFrom(RestContext.request);
      String requestId = requiredHeader(RestContext.request, REQUEST_HEADER);
      String fingerprint = requiredHeader(
        RestContext.request,
        FINGERPRINT_HEADER
      );

      response.statusCode = 200;
      response.responseBody = Blob.valueOf(
        QuoteDocumentJsonAdapter.render(quoteId, requestId, fingerprint)
      );
    } catch (RequestException e) {
      writeError(400, 'INVALID_REQUEST', 'The retrieval request is invalid.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      String code = safeDomainCode(e.getMessage());
      Integer statusCode = code == 'QUOTE_NOT_FOUND' ? 404 : 409;
      writeError(statusCode, code, safeDomainMessage(code));
    } catch (Exception e) {
      writeError(
        500,
        'RETRIEVAL_FAILED',
        'The document payload could not be retrieved.'
      );
    }
  }

  private static Id quoteIdFrom(RestRequest request) {
    String rawId = routeQuoteId(request);
    return typedQuoteId(rawId);
  }

  private static String routeQuoteId(RestRequest request) {
    String requestUri = requiredRequestUri(request);
    String prefix = '/quote-document-totals/v2/quotes/';
    Integer prefixAt = requestUri.indexOf(prefix);
    if (prefixAt < 0) {
      throw new RequestException();
    }
    String rawId = requestUri.substring(prefixAt + prefix.length());
    if (rawId.contains('/')) {
      throw new RequestException();
    }
    if (!hasSalesforceIdLength(rawId)) {
      throw new RequestException();
    }

    return rawId;
  }

  private static String requiredRequestUri(RestRequest request) {
    if (request == null) {
      throw new RequestException();
    }
    if (String.isBlank(request.requestURI)) {
      throw new RequestException();
    }
    return request.requestURI;
  }

  private static Boolean hasSalesforceIdLength(String rawId) {
    if (rawId == null) {
      return false;
    }
    return rawId.length() == 15 || rawId.length() == 18;
  }

  private static Id typedQuoteId(String rawId) {
    try {
      Id quoteId = (Id) rawId;
      if (quoteId.getSObjectType() != SBQQ__Quote__c.SObjectType) {
        throw new RequestException();
      }
      return quoteId;
    } catch (StringException e) {
      throw new RequestException();
    }
  }

  private static String requiredHeader(RestRequest request, String name) {
    String value = request == null ? null : request.headers.get(name);
    if (
      String.isBlank(value) ||
      value.length() > 255 ||
      value.contains('\r') ||
      value.contains('\n')
    ) {
      throw new RequestException();
    }
    return value;
  }

  private static String safeDomainCode(String message) {
    String candidate = String.isBlank(message)
      ? ''
      : message.substringBefore(':').trim();
    return Pattern.matches('^[A-Z][A-Z0-9_]{2,63}$', candidate)
      ? candidate
      : 'SNAPSHOT_REJECTED';
  }

  private static String safeDomainMessage(String code) {
    if (code == 'QUOTE_NOT_FOUND') {
      return 'No accessible Quote matches the request.';
    }
    if (code == 'SNAPSHOT_NOT_READY') {
      return 'The generated snapshot is not ready.';
    }
    if (code == 'SNAPSHOT_MOVED') {
      return 'The snapshot changed after generation. Generate again and use the new identity.';
    }
    if (
      code == 'PAYLOAD_HASH_MISSING' ||
      code == 'PAYLOAD_INTEGRITY_MISMATCH'
    ) {
      return 'The generated snapshot failed its integrity check.';
    }
    return 'The generated snapshot cannot be rendered.';
  }

  private static void writeError(
    Integer statusCode,
    String code,
    String message
  ) {
    RestContext.response.statusCode = statusCode;
    RestContext.response.responseBody = Blob.valueOf(
      JSON.serialize(new ErrorEnvelope(code, message))
    );
  }

  private class ErrorEnvelope {
    public ErrorDetail error;

    private ErrorEnvelope(String code, String message) {
      error = new ErrorDetail(code, message);
    }
  }

  private class ErrorDetail {
    public String code;
    public String message;

    private ErrorDetail(String code, String message) {
      this.code = code;
      this.message = message;
    }
  }

  private class RequestException extends Exception {
  }
}
