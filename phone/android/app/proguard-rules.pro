# Unity(C#)가 AndroidJavaClass("ai.allo.allo_phone.ExploreBridge") 로 이름을 찾아 부른다.
# release 빌드의 코드 축소(R8)가 이 클래스를 지우면 Unity → Flutter 메시지(ready·tap·care…)가 끊긴다.
-keep class ai.allo.allo_phone.ExploreBridge { *; }
