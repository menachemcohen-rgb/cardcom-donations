<?php
use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\Attributes\RunInSeparateProcess;
use PHPUnit\Framework\TestCase;

final class AmountConfigTest extends TestCase {
    public function test_defaults(): void {
        $this->assertSame(1.0, Org_Form::min_amount());
        $this->assertSame(50.0, Org_Form::max_amount());
        $this->assertSame([1, 2, 3, 5, 10], Org_Form::presets());
    }

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function test_presets_from_wp_config_drop_out_of_range_values(): void {
        define('ORG_DONATION_PRESETS', '2, 4,abc, 80');
        define('ORG_DONATION_MAX_AMOUNT', '60');
        $this->assertSame(60.0, Org_Form::max_amount());
        $this->assertSame([2, 4], Org_Form::presets());
    }

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function test_invalid_min_falls_back(): void {
        define('ORG_DONATION_MIN_AMOUNT', '-3');
        $this->assertSame(1.0, Org_Form::min_amount());
    }
}
