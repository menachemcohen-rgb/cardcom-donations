<?php
use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\Attributes\RunInSeparateProcess;
use PHPUnit\Framework\TestCase;

/** N122: sites that may embed the form (ORG_DONATION_FRAME_ANCESTORS). */
final class FrameAncestorsTest extends TestCase {
    public function test_default_is_unchanged(): void {
        $this->assertSame('', Org_Return_Endpoint::extra_frame_ancestors());
        $this->assertSame("frame-ancestors 'self'", Org_Return_Endpoint::frame_ancestors("'self'"));
        $this->assertSame('frame-ancestors https://secure.cardcom.solutions https://www.example.org.il',
            Org_Return_Endpoint::frame_ancestors('https://secure.cardcom.solutions https://www.example.org.il'));
    }

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function test_crm_origins_are_added_to_both_headers(): void {
        define('ORG_DONATION_FRAME_ANCESTORS', 'https://crm.ato770.com https://crm-dev.ato770.com');
        $this->assertSame("frame-ancestors 'self' https://crm.ato770.com https://crm-dev.ato770.com",
            Org_Return_Endpoint::frame_ancestors("'self'"));
        $this->assertSame('frame-ancestors https://secure.cardcom.solutions https://www.ato770.com https://crm.ato770.com https://crm-dev.ato770.com',
            Org_Return_Endpoint::frame_ancestors('https://secure.cardcom.solutions https://www.ato770.com'));
    }

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function test_only_https_origins_are_kept(): void {
        define('ORG_DONATION_FRAME_ANCESTORS', "https://CRM.ato770.com/, http://crm.ato770.com *  'unsafe-inline'; https://a.b/path https://x.org:8443 https://crm.ato770.com");
        $this->assertSame('https://crm.ato770.com https://x.org:8443', Org_Return_Endpoint::extra_frame_ancestors());
    }
}
