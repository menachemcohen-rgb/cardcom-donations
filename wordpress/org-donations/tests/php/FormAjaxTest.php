<?php
use PHPUnit\Framework\TestCase;

/** E2E fixes 1, 4, 5: no card session for an invalid form; one pledge per LowProfileId; only real submissions are rate-counted. */
final class FormAjaxTest extends TestCase
{
    private const LP = '0f3c2b1a-1111-2222-3333-444455556666';

    protected function setUp(): void
    {
        $GLOBALS['orgdon_test_transients'] = ['orgdon_sf_token' => 'tok', 'orgdon_sf_instance' => 'https://org.my.salesforce.com'];
        $GLOBALS['orgdon_test_options'] = [];
        $GLOBALS['orgdon_test_http'] = [];
        $GLOBALS['orgdon_test_http_reply'] = function ($url, $args) {
            if (str_ends_with($url, '/donations/lowprofile'))
                return ['code' => 200, 'body' => json_encode(['lowProfileId' => self::LP, 'url' => 'https://secure.cardcom.solutions/EA/x', 'expiresAt' => '2030-01-01T00:00:00Z'])];
            return ['code' => 200, 'body' => json_encode(['pledgeId' => '006x', 'status' => 'Pending_Verification'])];
        };
        $_SERVER['REMOTE_ADDR'] = '203.0.113.9';
        $_POST = [];
    }

    private function form(array $over = []): array
    {
        return array_merge(['first_name' => 'ישראל', 'last_name' => 'ישראלי', 'email' => 'a@example.com', 'phone' => '0521234567',
            'tax_id' => '', 'shacharit_amount' => '3', 'frequency' => 'OnceDaily', 'terms' => '1'], $over);
    }

    private function call(string $method, array $post): OrgdonTestJson
    {
        $_POST = $post;
        try { Org_Form::$method(); } catch (OrgdonTestJson $j) { return $j; }
        $this->fail('no JSON response');
    }

    private function sfCalls(string $path): int
    {
        return count(array_filter($GLOBALS['orgdon_test_http'], fn($u) => str_ends_with($u, $path)));
    }

    public function testNoCardSessionForAnInvalidForm(): void
    {
        foreach (['0', '51', '3.333', ''] as $amount) {
            $r = $this->call('ajax_lp', $this->form(['shacharit_amount' => $amount]));
            $this->assertFalse($r->ok, "amount $amount");
            $this->assertSame(422, $r->status);
            $this->assertArrayHasKey('shacharit_amount', $r->data['fields']);
            $this->assertSame('סכום לא תקין – נא לבחור סכום בין 1 ל-50 ₪', $r->data['fields']['shacharit_amount'], 'existing message text');
        }
        $r = $this->call('ajax_lp', $this->form(['email' => 'nope', 'phone' => '03-1234567', 'first_name' => '']));
        $this->assertSame(422, $r->status);
        $this->assertEqualsCanonicalizing(['email', 'phone', 'first_name'], array_keys($r->data['fields']));
        $this->assertSame(0, $this->sfCalls('/donations/lowprofile'), 'Cardcom session never created');

        $r = $this->call('ajax_lp', $this->form());
        $this->assertTrue($r->ok);
        $this->assertSame(self::LP, $r->data['lpId']);
        $this->assertSame(1, $this->sfCalls('/donations/lowprofile'));
    }

    public function testOneLowProfileIdGivesOnePledge(): void
    {
        $first = $this->call('ajax_submit', $this->form(['lp_id' => self::LP]));
        $this->assertTrue($first->ok);
        $again = $this->call('ajax_submit', $this->form(['lp_id' => self::LP]));
        $this->assertTrue($again->ok, 'a retry gets the same success');
        $this->assertSame($first->data['message'], $again->data['message']);
        $this->assertSame(1, $this->sfCalls('/donations/pledge'), 'Salesforce called once');
        $this->assertSame([], $GLOBALS['orgdon_test_options'], 'lock released');
    }

    public function testConcurrentSubmitWaitsInsteadOfCallingSalesforce(): void
    {
        add_option('orgdon_lock_' . md5(strtolower(self::LP)), time());
        $r = $this->call('ajax_submit', $this->form(['lp_id' => self::LP]));
        $this->assertFalse($r->ok);
        $this->assertSame(409, $r->status);
        $this->assertTrue($r->data['pending']);
        $this->assertSame(0, $this->sfCalls('/donations/pledge'));
    }

    public function testStaleLockIsTakenOver(): void
    {
        add_option('orgdon_lock_' . md5(strtolower(self::LP)), time() - 3600);
        $this->assertTrue($this->call('ajax_submit', $this->form(['lp_id' => self::LP]))->ok);
    }

    public function testAlreadyUsedInSalesforceIsAnsweredAsDone(): void
    {
        $GLOBALS['orgdon_test_http_reply'] = fn($u, $a) => ['code' => 400, 'body' => json_encode(['error' => 'LP_ALREADY_USED'])];
        $r = $this->call('ajax_submit', $this->form(['lp_id' => self::LP]));
        $this->assertTrue($r->data['done']);
        $this->assertTrue($this->call('ajax_submit', $this->form(['lp_id' => self::LP]))->ok, 'remembered as done');
    }

    public function testValidationErrorsAndPageLoadsAreNotRateCounted(): void
    {
        for ($i = 0; $i < 20; $i++) {
            $r = $this->call('ajax_submit', $this->form(['shacharit_amount' => '0', 'lp_id' => self::LP]));
            $this->assertSame(422, $r->status, "attempt $i is a validation error, not a rate-limit block");
        }
        $this->assertTrue(Org_Rate_Limiter::allowed('submit', Org_Form::submit_max()));
        // real submissions (each with its own card session) are counted
        for ($i = 0; $i < Org_Form::submit_max(); $i++) {
            $this->assertTrue($this->call('ajax_submit', $this->form(['lp_id' => sprintf('0f3c2b1a-1111-2222-3333-%012d', $i)]))->ok);
        }
        $blocked = $this->call('ajax_submit', $this->form(['lp_id' => '0f3c2b1a-1111-2222-3333-999999999999']));
        $this->assertSame(429, $blocked->status);
    }

    /** The JSON sent to Salesforce /donations/pledge for each frequency. */
    public function testPledgePayloadPerFrequency(): void
    {
        $sent = [];
        $GLOBALS['orgdon_test_http_reply'] = function ($url, $args) use (&$sent) {
            $sent[] = json_decode($args['body'], true);
            return ['code' => 200, 'body' => json_encode(['pledgeId' => '006x', 'status' => 'Pending_Verification'])];
        };
        $cases = [
            ['TwiceDaily', ['shacharit_amount' => '3', 'mincha_amount' => '5'], 3, 5],
            ['TwiceDaily', ['shacharit_amount' => '4', 'mincha_amount' => '', 'same_amount' => '1'], 4, 4],
            ['OnceDaily',  ['shacharit_amount' => '2', 'mincha_amount' => '9'], 2, null],
            ['MinchaOnly', ['shacharit_amount' => '', 'mincha_amount' => '6.5'], null, 6.5],
        ];
        foreach ($cases as $i => [$freq, $amounts, $sh, $mi]) {
            $lp = sprintf('0f3c2b1a-1111-2222-3333-%012d', 100 + $i);
            $this->assertTrue($this->call('ajax_submit', array_merge($this->form(['frequency' => $freq, 'lp_id' => $lp]), $amounts))->ok, $freq);
            $p = $sent[$i];
            $this->assertSame($freq, $p['frequency']);
            $this->assertEquals($sh, $p['shacharitAmount'], "$freq shacharit");
            $this->assertEquals($mi, $p['minchaAmount'], "$freq mincha");
            $this->assertArrayHasKey('shacharitAmount', $p, 'null is sent, not omitted');
            $this->assertArrayHasKey('minchaAmount', $p);
            $this->assertArrayNotHasKey('amount', $p);
            $this->assertSame($lp, $p['lowProfileId']);
            $this->assertSame('203.0.113.9', $p['clientIp']);
        }
    }

    public function testSalesforceValidationFieldsReachTheAmountInputs(): void
    {
        $GLOBALS['orgdon_test_http_reply'] = fn($u, $a) => ['code' => 400, 'body' => json_encode(['error' => 'VALIDATION', 'fields' => ['minchaAmount']])];
        $r = $this->call('ajax_submit', $this->form(['frequency' => 'MinchaOnly', 'mincha_amount' => '3', 'lp_id' => self::LP]));
        $this->assertSame(422, $r->status);
        $this->assertSame(['mincha_amount'], array_keys($r->data['fields']));
    }

    public function testDefaultsWhenConstantsAreMissing(): void
    {
        $this->assertSame(600, Org_Form::window());
        $this->assertSame(5, Org_Form::submit_max());
        $this->assertSame(10, Org_Form::lp_max());
    }
}
