<?php
use PHPUnit\Framework\TestCase;

/** Donor page: Shacharit/Mincha amounts, card replacement (card only), no stop endpoint. */
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
            if (str_ends_with($url, '/donor/card/status'))
                return ['code' => 200, 'body' => json_encode(['status' => 'Completed', 'last4' => '1234', 'amount' => 7, 'shacharitAmount' => 7, 'minchaAmount' => 5])];
            if (str_ends_with($url, '/donor/amount'))
                return ['code' => 200, 'body' => json_encode(['ok' => true, 'changed' => true, 'shacharitAmount' => 4, 'minchaAmount' => 6.5, 'amount' => 4])];
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

    public function testCardSendsNoAmount(): void
    {
        $r = $this->call('ajax_card', ['amount' => '7', 'shacharitAmount' => '7']);
        $this->assertTrue($r->ok);
        $this->assertSame(['token', 'returnUrlBase', 'clientIp'], array_keys($GLOBALS['orgdon_test_sent'][0]), 'card change = card only');
    }

    public function testCardStatusReturnsTheAmounts(): void
    {
        $r = $this->call('ajax_card_status', ['lpId' => 'lp-card-0000000009']);
        $this->assertSame('Completed', $r->data['status']);
        $this->assertSame('1234', $r->data['last4']);
        $this->assertSame(7.0, $r->data['shacharitAmount']);
        $this->assertSame(5.0, $r->data['minchaAmount']);
    }

    public function testAmountForwardsOnlyTheGivenPrayers(): void
    {
        $r = $this->call('ajax_amount', ['shacharitAmount' => '4', 'minchaAmount' => '6,5']);
        $this->assertTrue($r->ok);
        $this->assertStringEndsWith('/donor/amount', $GLOBALS['orgdon_test_http'][0]);
        $sent = $GLOBALS['orgdon_test_sent'][0];
        $this->assertSame(['token', 'shacharitAmount', 'minchaAmount', 'clientIp'], array_keys($sent));
        $this->assertEquals(4, $sent['shacharitAmount']);
        $this->assertEquals(6.5, $sent['minchaAmount']);
        $this->assertSame('הסכום עודכן: שחרית 4.00 ₪, מנחה 6.50 ₪, החל מהחיוב הבא. תודה!', $r->data['message']);
        $this->assertSame(4.0, $r->data['shacharitAmount']);
        $this->assertSame(6.5, $r->data['minchaAmount']);

        $GLOBALS['orgdon_test_sent'] = [];
        $GLOBALS['orgdon_test_http_reply'] = function ($u, $args) {
            $GLOBALS['orgdon_test_sent'][] = json_decode($args['body'], true);
            return ['code' => 200, 'body' => json_encode(['ok' => true, 'changed' => true, 'shacharitAmount' => null, 'minchaAmount' => 3, 'amount' => 3])];
        };
        $r = $this->call('ajax_amount', ['minchaAmount' => '3']);
        $this->assertArrayNotHasKey('shacharitAmount', $GLOBALS['orgdon_test_sent'][0], 'omitted when not included');
        $this->assertSame('הסכום עודכן: מנחה 3.00 ₪, החל מהחיוב הבא. תודה!', $r->data['message']);
    }

    public function testAmountUnchanged(): void
    {
        $GLOBALS['orgdon_test_http_reply'] = fn($u, $a) => ['code' => 200, 'body' => json_encode(['ok' => true, 'changed' => false, 'shacharitAmount' => 3, 'minchaAmount' => null, 'amount' => 3])];
        $r = $this->call('ajax_amount', ['shacharitAmount' => '3']);
        $this->assertSame('הסכומים לא השתנו.', $r->data['message']);
    }

    public function testAmountBadInputNeverReachesSalesforce(): void
    {
        $this->assertSame(422, $this->call('ajax_amount', ['shacharitAmount' => '7.123'])->status);
        $this->assertSame(422, $this->call('ajax_amount', [])->status, 'no amount at all');
        $this->assertSame(422, $this->call('ajax_amount', ['amount' => '5'])->status, 'the old single amount is not accepted');
        $this->assertSame([], $GLOBALS['orgdon_test_http']);
    }

    public function testAmountOutOfRangeFromSalesforce(): void
    {
        $GLOBALS['orgdon_test_http_reply'] = fn($u, $a) => ['code' => 400, 'body' => json_encode(['error' => 'AMOUNT_RANGE'])];
        $this->assertSame(422, $this->call('ajax_amount', ['minchaAmount' => '999'])->status);
    }

    public function testContextMapsFrequencyAndAmounts(): void
    {
        foreach ([
            ['TwiceDaily', 3, 5, 'שחרית ומנחה', 3.0, 5.0],
            ['OnceDaily', 3, null, 'רק שחרית', 3.0, null],
            ['MinchaOnly', null, 4, 'רק מנחה', null, 4.0],
        ] as [$code, $sh, $mi, $he, $esh, $emi]) {
            $GLOBALS['orgdon_test_http_reply'] = fn($u, $a) => ['code' => 200, 'body' => json_encode([
                'action' => 'amount', 'firstName' => 'דנה', 'amount' => $sh ?? $mi, 'frequency' => $code,
                'shacharitAmount' => $sh, 'minchaAmount' => $mi, 'last4' => '1234', 'expMMYY' => '0930',
                'minAmount' => 1, 'maxAmount' => 50, 'presets' => [1, 3, 5]])];
            $d = $this->call('ajax_context', [])->data;
            $this->assertSame($he, $d['frequency']);
            $this->assertSame($code, $d['frequencyCode']);
            $this->assertSame($esh, $d['shacharitAmount'], $code);
            $this->assertSame($emi, $d['minchaAmount'], $code);
        }
    }

    public function testStopEndpointIsGone(): void
    {
        $this->assertFalse(method_exists(Org_Portal::class, 'ajax_stop'));
        $src = file_get_contents(dirname(__DIR__, 2) . '/includes/class-org-portal.php')
             . file_get_contents(dirname(__DIR__, 2) . '/templates/portal.php')
             . file_get_contents(dirname(__DIR__, 2) . '/assets/donor-portal.js');
        $this->assertStringNotContainsString('/donor/stop', $src);
        $this->assertStringNotContainsString('הפסקת', $src);
        $this->assertStringNotContainsString("'stop'", $src);
    }
}
