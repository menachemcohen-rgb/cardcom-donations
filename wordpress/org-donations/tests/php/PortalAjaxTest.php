<?php
use PHPUnit\Framework\TestCase;

/** Donor page: stop the pledge, and a new amount sent together with the card replacement. */
final class PortalAjaxTest extends TestCase
{
    private const TOKEN = 'eyJwIjoiMDA2eCIsImEiOiJjYXJkIiwidiI6MX0.signature_abcdefghij';

    protected function setUp(): void
    {
        $GLOBALS['orgdon_test_transients'] = ['orgdon_sf_token' => 'tok', 'orgdon_sf_instance' => 'https://org.my.salesforce.com'];
        $GLOBALS['orgdon_test_http'] = [];
        $GLOBALS['orgdon_test_sent'] = [];
        $GLOBALS['orgdon_test_http_reply'] = function ($url, $args) {
            $GLOBALS['orgdon_test_sent'][] = json_decode($args['body'], true);
            if (str_ends_with($url, '/donor/card'))
                return ['code' => 200, 'body' => json_encode(['lowProfileId' => 'lp-card-0000000009', 'url' => 'https://secure.cardcom.solutions/EA/x', 'expiresAt' => 'x'])];
            if (str_ends_with($url, '/donor/stop'))
                return ['code' => 200, 'body' => json_encode(['ok' => true, 'status' => 'Stopped'])];
            if (str_ends_with($url, '/donor/card/status'))
                return ['code' => 200, 'body' => json_encode(['status' => 'Completed', 'last4' => '1234', 'amount' => 7])];
            return ['code' => 404, 'body' => '{}'];
        };
        $_SERVER['REMOTE_ADDR'] = '203.0.113.' . random_int(1, 250);
    }

    private function call(string $method, array $post): OrgdonTestJson
    {
        $_POST = $post + ['token' => self::TOKEN, 'nonce' => 'n'];
        try { Org_Portal::$method(); } catch (OrgdonTestJson $j) { return $j; }
        $this->fail('no JSON response');
    }

    public function testCardCarriesTheNewAmount(): void
    {
        $r = $this->call('ajax_card', ['amount' => '7']);
        $this->assertTrue($r->ok);
        $this->assertEquals(7, $GLOBALS['orgdon_test_sent'][0]['amount']);
    }

    public function testCardWithoutAmountSendsNone(): void
    {
        $this->assertTrue($this->call('ajax_card', [])->ok);
        $this->assertArrayNotHasKey('amount', $GLOBALS['orgdon_test_sent'][0]);
    }

    public function testCardWithABadAmountNeverReachesSalesforce(): void
    {
        $r = $this->call('ajax_card', ['amount' => '7.123']);
        $this->assertSame(422, $r->status);
        $this->assertSame([], $GLOBALS['orgdon_test_http']);
    }

    public function testCardAmountOutOfRangeFromSalesforce(): void
    {
        $GLOBALS['orgdon_test_http_reply'] = fn($u, $a) => ['code' => 400, 'body' => json_encode(['error' => 'AMOUNT_RANGE'])];
        $r = $this->call('ajax_card', ['amount' => '999']);
        $this->assertSame(422, $r->status);
        $this->assertSame('amount', $r->data['field']);
    }

    public function testCardStatusReturnsTheAmount(): void
    {
        $r = $this->call('ajax_card_status', ['lpId' => 'lp-card-0000000009']);
        $this->assertSame(7.0, $r->data['amount']);
        $this->assertSame('1234', $r->data['last4']);
    }

    public function testStopNeedsTheConfirmation(): void
    {
        $r = $this->call('ajax_stop', []);
        $this->assertSame(400, $r->status);
        $this->assertSame([], $GLOBALS['orgdon_test_http'], 'nothing sent without the confirm step');
        $r = $this->call('ajax_stop', ['confirm' => '1']);
        $this->assertTrue($r->ok);
        $this->assertStringEndsWith('/donor/stop', $GLOBALS['orgdon_test_http'][0]);
    }

    public function testStopWithAnInvalidLink(): void
    {
        $GLOBALS['orgdon_test_http_reply'] = fn($u, $a) => ['code' => 403, 'body' => json_encode(['error' => 'LINK_INVALID'])];
        $r = $this->call('ajax_stop', ['confirm' => '1']);
        $this->assertSame(403, $r->status);
        $this->assertTrue($r->data['invalid']);
    }
}
