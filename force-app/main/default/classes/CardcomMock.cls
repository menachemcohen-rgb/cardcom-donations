/**
 * HttpCalloutMock for the Cardcom API (B8). Responses are scripted per path ("LowProfile/GetLpResult", ...):
 * queued responses are used in order, then the path's default. Every request is recorded for assertions. "TIMEOUT" throws.
 */
@IsTest
public class CardcomMock implements HttpCalloutMock {
  public static final String TIMEOUT = 'TIMEOUT';
  /** Throws what the platform throws when the running user can't use the Named/External Credential. */
  public static final String CREDENTIAL_ERROR = 'CREDENTIAL_ERROR';
  public static final String CREDENTIAL_MESSAGE =
    'We couldn\'t access the credential(s). You might not have the required permissions, or the external credential "Cardcom_EC" might not exist.';
  final Map<String, List<Object[]>> queued = new Map<String, List<Object[]>>();
  final Map<String, Object[]> defaults = new Map<String, Object[]>();
  public List<HttpRequest> requests = new List<HttpRequest>();

  public static CardcomMock install() {
    CardcomMock m = new CardcomMock();
    Test.setMock(HttpCalloutMock.class, m);
    return m;
  }

  /** Next response for a path (status, body as Map or String, or TIMEOUT). */
  public CardcomMock enqueue(String path, Integer status, Object body) {
    if (!queued.containsKey(path))
      queued.put(path, new List<Object[]>());
    queued.get(path).add(new List<Object>{ status, body });
    return this;
  }

  /** Response used for a path once its queue is empty. */
  public CardcomMock always(String path, Integer status, Object body) {
    defaults.put(path, new List<Object>{ status, body });
    return this;
  }

  public HttpResponse respond(HttpRequest req) {
    requests.add(req);
    String path = req.getEndpoint().substringAfter('api/v11/');
    Object[] r;
    if (queued.containsKey(path) && !queued.get(path).isEmpty())
      r = queued.get(path).remove(0);
    else
      r = defaults.get(path);
    if (r == null)
      throw new CalloutException('CardcomMock: no response scripted for ' + path);
    if (r[1] == TIMEOUT)
      throw new CalloutException('Read timed out');
    if (r[1] == CREDENTIAL_ERROR)
      throw new CalloutException(CREDENTIAL_MESSAGE);
    HttpResponse res = new HttpResponse();
    res.setStatusCode((Integer) r[0]);
    res.setHeader('Content-Type', 'application/json');
    res.setBody(r[1] instanceof String ? (String) r[1] : JSON.serialize(r[1]));
    return res;
  }

  public List<HttpRequest> requestsTo(String path) {
    List<HttpRequest> out = new List<HttpRequest>();
    for (HttpRequest r : requests)
      if (r.getEndpoint().endsWith(path))
        out.add(r);
    return out;
  }

  public Map<String, Object> lastBody(String path) {
    List<HttpRequest> rs = requestsTo(path);
    return rs.isEmpty() ? null : (Map<String, Object>) JSON.deserializeUntyped(rs[rs.size() - 1].getBody());
  }

  // ---- canned bodies (B5.1, B5.3) ----
  public static Map<String, Object> lpCreated(String lowProfileId) {
    return new Map<String, Object>{
      'ResponseCode' => 0,
      'Description' => 'OK',
      'LowProfileId' => lowProfileId,
      'Url' => 'https://secure.cardcom.solutions/EA/' + lowProfileId
    };
  }

  public static Map<String, Object> lpSuccess(String lowProfileId, String returnValue) {
    return new Map<String, Object>{
      'ResponseCode' => 0,
      'Description' => '',
      'TerminalNumber' => 1001,
      'LowProfileId' => lowProfileId,
      'TranzactionId' => 0,
      'ReturnValue' => returnValue,
      'Operation' => 'CreateTokenOnly',
      'TokenInfo' => new Map<String, Object>{
        'Token' => 'tok-' + lowProfileId,
        'TokenExDate' => '20301231',
        'CardYear' => 2028,
        'CardMonth' => 9,
        'TokenApprovalNumber' => '0012345',
        'CardOwnerIdentityNumber' => '000000000'
      },
      'TranzactionInfo' => null
    };
  }

  public static Map<String, Object> lpPending(String lowProfileId) {
    return new Map<String, Object>{
      'ResponseCode' => 5117,
      'Description' => 'pending',
      'LowProfileId' => lowProfileId,
      'ReturnValue' => 'SIGNUP-x'
    };
  }

  public static Map<String, Object> lpFailed(String lowProfileId) {
    return new Map<String, Object>{
      'ResponseCode' => 4,
      'Description' => 'declined',
      'LowProfileId' => lowProfileId,
      'ReturnValue' => 'SIGNUP-x',
      'TokenInfo' => null
    };
  }
}
