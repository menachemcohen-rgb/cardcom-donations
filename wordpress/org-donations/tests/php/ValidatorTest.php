<?php
use PHPUnit\Framework\TestCase;

final class ValidatorTest extends TestCase
{
    private function input(array $over = []): array
    {
        return $over + [
            'first_name' => 'ישראל', 'last_name' => 'ישראלי', 'email' => 'donor@example.com', 'phone' => '052-123-4567',
            'tax_id' => '', 'amount' => '3', 'frequency' => 'TwiceDaily', 'terms' => '1',
            'lp_id' => '0f3c2b1a-1234-4abc-9def-0123456789ab',
        ];
    }

    public function testPhoneFormats(): void
    {
        foreach (['0521234567', '052-123-4567', '+972 52 123 4567', '972521234567', '00972521234567', '521234567'] as $p) {
            $this->assertSame('0521234567', Org_Validator::phone($p), $p);
        }
        $this->assertNull(Org_Validator::phone('03-1234567'), 'landline');
        $this->assertNull(Org_Validator::phone('05212345'), 'too short');
        $this->assertNull(Org_Validator::phone(''));
    }

    public function testIsraeliId(): void
    {
        $this->assertSame('123456782', Org_Validator::il_id('123456782'));
        $this->assertSame('000000018', Org_Validator::il_id('18'), 'left-padded to 9 digits');
        $this->assertSame('123456782', Org_Validator::il_id('12345678-2'));
        $this->assertNull(Org_Validator::il_id('123456789'), 'check digit (TC05)');
        $this->assertNull(Org_Validator::il_id('1234567890'), 'more than 9 digits');
        $this->assertNull(Org_Validator::il_id(''));
    }

    public function testValidSignupBuildsTheSalesforcePayload(): void
    {
        $v = Org_Validator::signup($this->input(['tax_id' => '18']), 1, 50);
        $this->assertSame([], $v['errors']);
        $d = $v['data'];
        $this->assertSame('ישראל', $d['firstName']);
        $this->assertSame('0521234567', $d['phone']);
        $this->assertSame('000000018', $d['taxId']);
        $this->assertSame(3.0, $d['amount']);
        $this->assertSame('TwiceDaily', $d['frequency']);
        $this->assertTrue($d['termsAccepted']);
        $this->assertSame(
            ['firstName', 'lastName', 'email', 'phone', 'taxId', 'amount', 'frequency', 'termsAccepted', 'lowProfileId'],
            array_keys($d), 'B4 /donations/pledge keys (clientIp is added by Org_Form)'
        );
    }

    public function testAmountRules(): void
    {
        foreach (['1', '50', '3.5', '3,50', '12.25'] as $ok) {
            $this->assertArrayNotHasKey('amount', Org_Validator::signup($this->input(['amount' => $ok]), 1, 50)['errors'], $ok);
        }
        foreach (['0.5', '50.01', '51', '3.333', 'abc', '', '-3'] as $bad) {
            $this->assertArrayHasKey('amount', Org_Validator::signup($this->input(['amount' => $bad]), 1, 50)['errors'], $bad);
        }
        $this->assertStringContainsString('בין 1 ל-50', Org_Validator::signup($this->input(['amount' => '99']), 1, 50)['errors']['amount']);
    }

    public function testEveryRequiredFieldHasAHebrewError(): void
    {
        $e = Org_Validator::signup([], 1, 50)['errors'];
        foreach (['first_name', 'last_name', 'email', 'phone', 'amount', 'frequency', 'terms', 'card'] as $k) {
            $this->assertArrayHasKey($k, $e, $k);
            $this->assertMatchesRegularExpression('/[\x{0590}-\x{05FF}]/u', $e[$k], "$k message is Hebrew");
        }
        $this->assertArrayNotHasKey('tax_id', $e, 'the Israeli ID is optional');
        $this->assertArrayHasKey('tax_id', Org_Validator::signup($this->input(['tax_id' => '123456789']), 1, 50)['errors']);
        $this->assertArrayHasKey('first_name', Org_Validator::signup($this->input(['first_name' => str_repeat('א', 41)]), 1, 50)['errors']);
        $this->assertArrayHasKey('card', Org_Validator::signup($this->input(['lp_id' => 'not-an-id']), 1, 50)['errors']);
        $this->assertArrayHasKey('frequency', Org_Validator::signup($this->input(['frequency' => 'Hourly']), 1, 50)['errors']);
    }

    public function testSalesforceValidationFieldsAreMappedForTheForm(): void
    {
        $this->assertSame(
            ['first_name' => 'נא לבדוק שדה זה', 'terms' => 'נא לבדוק שדה זה', 'card' => 'נא לבדוק שדה זה'],
            Org_Form::sf_fields(['firstName', 'termsAccepted', 'lowProfileId', 'unknown', 42])
        );
    }

    public function testCardIsNotRequiredBeforeTheCardSession(): void
    {
        $in = ['first_name' => 'א', 'last_name' => 'ב', 'email' => 'a@example.com', 'phone' => '0521234567',
               'amount' => '3', 'frequency' => 'OnceDaily', 'terms' => '1'];
        $this->assertSame([], Org_Validator::signup($in, 1, 50, false)['errors']);
        $this->assertArrayHasKey('card', Org_Validator::signup($in, 1, 50)['errors']);
        $this->assertArrayHasKey('amount', Org_Validator::signup(['amount' => '51'] + $in, 1, 50, false)['errors']);
    }
}
