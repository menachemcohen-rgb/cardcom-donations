<?php
use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\Attributes\RunInSeparateProcess;
use PHPUnit\Framework\TestCase;

/** N123: amount buttons and min/max come from Salesforce, with a cache and fallbacks. */
final class SettingsFromSalesforceTest extends TestCase {
    private int $calls = 0;

    protected function setUp(): void {
        $GLOBALS['orgdon_test_transients'] = ['orgdon_sf_token' => 'tok', 'orgdon_sf_instance' => 'https://org.my.salesforce.com'];
        $GLOBALS['orgdon_test_options'] = [];
        $GLOBALS['orgdon_test_http'] = [];
        $this->reply(200, ['presets' => [2, 4, 6, 50], 'minAmount' => 2, 'maxAmount' => 30]);
        Org_Settings::reset();
    }

    protected function tearDown(): void { Org_Settings::reset(); }

    private function reply(int $code, $body): void {
        $GLOBALS['orgdon_test_http_reply'] = function ($url, $args) use ($code, $body) {
            $this->calls++;
            $this->assertStringEndsWith('/services/apexrest/donations/settings', $url);
            return ['code' => $code, 'body' => is_string($body) ? $body : json_encode($body)];
        };
    }

    private function down(): void {
        $GLOBALS['orgdon_test_http_reply'] = function () { $this->calls++; throw new RuntimeException('network'); };
    }

    public function test_reads_salesforce_and_drops_buttons_outside_the_range(): void {
        $this->assertSame(2.0, Org_Form::min_amount());
        $this->assertSame(30.0, Org_Form::max_amount());
        $this->assertSame([2, 4, 6], Org_Form::presets(), '50 is above the Salesforce maximum');
        $this->assertSame('salesforce', Org_Settings::get()['source']);
        $this->assertSame(1, $this->calls, 'one call per page');
        $this->assertIsArray($GLOBALS['orgdon_test_transients']['orgdon_sf_settings'], 'cached for 10 minutes');
        $this->assertIsArray($GLOBALS['orgdon_test_options']['orgdon_sf_settings_last'], 'last good copy kept');
    }

    public function test_cached_copy_is_used_without_calling_salesforce(): void {
        Org_Settings::get();
        Org_Settings::reset();                     // next page load, transient still there
        $this->assertSame([2, 4, 6], Org_Form::presets());
        $this->assertSame(1, $this->calls);
    }

    public function test_salesforce_down_uses_the_last_saved_copy(): void {
        Org_Settings::get();
        Org_Settings::refresh();                   // the 10 minutes ran out
        $this->down();
        $this->assertSame([2, 4, 6], Org_Form::presets());
        $this->assertSame(30.0, Org_Form::max_amount());
        $this->assertSame('last', Org_Settings::get()['source']);
        Org_Settings::reset();
        Org_Settings::get();
        $this->assertSame(2, $this->calls, 'after a failure Salesforce is not asked again for a minute');
    }

    public function test_bad_answer_counts_as_failure(): void {
        $this->reply(200, ['pledgeId' => '006x']);
        $this->assertSame('default', Org_Settings::get()['source']);
        Org_Settings::reset(); unset($GLOBALS['orgdon_test_transients']['orgdon_sf_settings_retry']);
        $this->reply(200, ['presets' => [1], 'minAmount' => 10, 'maxAmount' => 5]);
        $this->assertSame('default', Org_Settings::get()['source'], 'min above max');
        Org_Settings::reset(); unset($GLOBALS['orgdon_test_transients']['orgdon_sf_settings_retry']);
        $this->reply(500, ['error' => 'INTERNAL']);
        $this->assertSame('default', Org_Settings::get()['source']);
    }

    public function test_no_saved_copy_and_no_constants_uses_the_defaults(): void {
        $this->down();
        $this->assertSame(1.0, Org_Form::min_amount());
        $this->assertSame(40.0, Org_Form::max_amount());
        $this->assertSame([1, 2, 3, 5, 10], Org_Form::presets());
    }

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function test_no_saved_copy_uses_the_wp_config_constants(): void {
        define('ORG_DONATION_PRESETS', '5,15,25,100');
        define('ORG_DONATION_MIN_AMOUNT', '5');
        define('ORG_DONATION_MAX_AMOUNT', '25');
        $this->down();
        $this->assertSame([5, 15, 25], Org_Form::presets(), '100 above the constant maximum');
        $this->assertSame('config', Org_Settings::get()['source']);
    }

    public function test_refresh_drops_the_cache_and_asks_salesforce_again(): void {
        Org_Settings::get();
        $this->reply(200, ['presets' => [7, 8], 'minAmount' => 1, 'maxAmount' => 40]);
        Org_Settings::refresh();
        $this->assertArrayNotHasKey('orgdon_sf_settings', $GLOBALS['orgdon_test_transients']);
        $this->assertSame([7, 8], Org_Form::presets());
        $this->assertSame(2, $this->calls);
    }

    public function test_validation_uses_the_salesforce_range(): void {
        $in = ['first_name' => 'א', 'last_name' => 'ב', 'email' => 'a@example.com', 'phone' => '0521234567',
               'shacharit_amount' => '35', 'frequency' => 'OnceDaily', 'terms' => '1'];
        $v = Org_Validator::signup($in, Org_Form::min_amount(), Org_Form::max_amount(), false);
        $this->assertArrayHasKey('shacharit_amount', $v['errors'], '35 is above the Salesforce maximum 30');
        $in['shacharit_amount'] = '30';
        $v = Org_Validator::signup($in, Org_Form::min_amount(), Org_Form::max_amount(), false);
        $this->assertArrayNotHasKey('shacharit_amount', $v['errors']);
    }
}
