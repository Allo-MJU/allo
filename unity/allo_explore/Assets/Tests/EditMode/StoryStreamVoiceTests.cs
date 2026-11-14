using Allo.App;
using Allo.Bridge;
using NUnit.Framework;

public class StoryStreamVoiceTests
{
    [Test] public void PcmHandlesOddNetworkBoundariesAndSignedLittleEndian()
    {
        var buffer = new StoryPcmBuffer(4);
        Assert.IsTrue(buffer.Append(new byte[]{0}, 1));
        Assert.IsTrue(buffer.Append(new byte[]{128,255,127,0,0}, 5));
        Assert.IsTrue(buffer.Finish());
        var output = new float[4]; buffer.Read(output);
        Assert.AreEqual(-1f, output[0]); Assert.AreEqual(32767f / 32768, output[1]);
        Assert.AreEqual(0f, output[2]); Assert.AreEqual(0f, output[3]);
    }
    [Test] public void CancelDropsQueuedAndLateSamples()
    {
        var buffer = new StoryPcmBuffer(4);
        buffer.Append(new byte[]{255,127},2); buffer.Cancel();
        Assert.IsFalse(buffer.Append(new byte[]{255,127},2));
        var output = new[]{1f,1f}; buffer.Read(output);
        CollectionAssert.AreEqual(new[]{0f,0f},output); Assert.AreEqual(0,buffer.Count);
    }
    [Test] public void OverflowAndTruncatedFramesFail()
    {
        var small = new StoryPcmBuffer(1);
        Assert.IsFalse(small.Append(new byte[]{1,0,1,0},4)); Assert.IsTrue(small.Failed);
        var odd = new StoryPcmBuffer(); odd.Append(new byte[]{1},1);
        Assert.IsFalse(odd.Finish());
    }
    [Test] public void DrainTimelineIncludesUnderrunAndHandedOffTail()
    {
        var buffer = new StoryPcmBuffer(8);
        buffer.Read(new float[4]); // First callback underflowed before new data arrived.
        buffer.Append(new byte[]{1,0,2,0},4);
        buffer.Read(new float[4]);
        Assert.AreEqual(0, buffer.Count);
        Assert.AreEqual(6, buffer.LastDataEndFrame); // Final audio is at frame 6, not queue-empty time.
        buffer.Read(new float[4]);
        Assert.AreEqual(6, buffer.LastDataEndFrame); // Later silence does not extend the tail.
    }
    [Test] public void HeadersMustExplicitlyMatchLittleEndianMonoPcm()
    {
        Assert.IsTrue(StoryStreamVoice.ValidAudioHeaders(200,"application/octet-stream","s16le","24000","1"));
        Assert.IsFalse(StoryStreamVoice.ValidAudioHeaders(200,"audio/L16","s16le","24000","1"));
        Assert.IsFalse(StoryStreamVoice.ValidAudioHeaders(200,"application/octet-stream","s16be","24000","1"));
        Assert.IsFalse(StoryStreamVoice.ValidAudioHeaders(200,"application/octet-stream","s16le","48000","1"));
        Assert.IsFalse(StoryStreamVoice.ValidAudioHeaders(200,"application/octet-stream","s16le","24000","2"));
        Assert.IsFalse(StoryStreamVoice.ValidAudioHeaders(401,"application/octet-stream","s16le","24000","1"));
    }
    [Test] public void EndpointRestrictionsAndTransientBridgeParsing()
    {
        Assert.IsTrue(StoryStreamVoice.ValidEndpoint("https://voice.example.com",false));
        Assert.IsFalse(StoryStreamVoice.ValidEndpoint("http://10.0.2.2:8090",false));
        Assert.IsTrue(StoryStreamVoice.ValidEndpoint("http://10.0.2.2:8090",true));
        Assert.IsFalse(StoryStreamVoice.ValidEndpoint("https://user:pass@voice.example.com",true));
        Assert.IsFalse(StoryStreamVoice.ValidEndpoint("https://voice.example.com?token=x",true));
        Assert.IsTrue(MessageParser.TryParse("{\"v\":1,\"type\":\"storyVoiceConfig\",\"requestId\":\"x\",\"token\":\"value\"}",out _,out var value));
        Assert.AreEqual("x",((StoryVoiceConfig)value).requestId);
    }
}
