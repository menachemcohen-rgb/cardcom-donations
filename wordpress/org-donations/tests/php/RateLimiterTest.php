<?php
use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\Attributes\RunInSeparateProcess;
use PHPUnit\Framework\TestCase;

final class RateLimiterTest extends TestCase
{
    protected function setUp(): void
    {
        $GLOBALS['orgdon_test_transients'] = [];
        $_SERVER['REMOTE_ADDR'] = '203.0.113.7';
        unset($_SERVER['HTTP_CF_CONNECTING_IP']);
    }

    public function testAllowsUpToTheLimitPerBucketAndIp(): void
    {
        for ($i = 0; $i < 10; $i++) $this->assertTrue(Org_Rate_Limiter::hit('lp', 10, 600), "call $i");
        $this->assertFalse(Org_Rate_Limiter::hit('lp', 10, 600), '11th call in the window');
        $this->assertTrue(Org_Rate_Limiter::hit('submit', 5, 600), 'other bucket is independent');
        $_SERVER['REMOTE_ADDR'] = '203.0.113.8';
        $this->assertTrue(Org_Rate_Limiter::hit('lp', 10, 600), 'other IP is independent');
    }

    public function testInvalidRemoteAddressFallsBack(): void
    {
        $_SERVER['REMOTE_ADDR'] = 'not-an-ip';
        $this->assertSame('0.0.0.0', Org_Rate_Limiter::ip());
    }

    public function testCloudflareHeaderIsIgnoredUnlessConfigured(): void
    {
        $_SERVER['HTTP_CF_CONNECTING_IP'] = '198.51.100.1';
        $this->assertSame('203.0.113.7', Org_Rate_Limiter::ip(), 'a client can send this header; not trusted by default (N62)');
    }

    #[RunInSeparateProcess]
    #[PreserveGlobalState(false)]
    public function testCloudflareHeaderIsUsedWhenBehindCloudflare(): void
    {
        define('ORG_BEHIND_CLOUDFLARE', true);
        $_SERVER['REMOTE_ADDR'] = '172.70.1.1';
        $_SERVER['HTTP_CF_CONNECTING_IP'] = '198.51.100.1';
        $this->assertSame('198.51.100.1', Org_Rate_Limiter::ip());
    }
}
