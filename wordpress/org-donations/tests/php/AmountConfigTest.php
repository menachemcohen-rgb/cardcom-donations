<?php
use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\Attributes\RunInSeparateProcess;
use PHPUnit\Framework\TestCase;

final class AmountConfigTest extends TestCase {
    public function test_defaults(): void {
        $this->assertSame(1.0, Org_Form::min_amount());
        $this->assertSame(25.0, Org_Form::max_amount());
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

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function test_presets_above_the_maximum_are_hidden(): void {
        define('ORG_DONATION_PRESETS', '1,5,10,25,30,50');
        $this->assertSame([1, 5, 10, 25], Org_Form::presets(), 'ATA-6: buttons above 25 are not shown');
    }

    public function test_frame_style_default_is_empty(): void {
        $this->assertSame('', Org_Form::frame_style());
    }

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function test_frame_heights_from_wp_config(): void {
        define('ORG_DONATION_FRAME_HEIGHT', '950');
        define('ORG_DONATION_FRAME_HEIGHT_MOBILE', '12px; color:red');
        $this->assertSame('--orgdon-frame-h:950px', Org_Form::frame_style(), 'bad value ignored');
    }
}
