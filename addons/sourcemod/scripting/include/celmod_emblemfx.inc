// |CelMod| emblem effects: what every emblem's shots and held aura look like.
//
// Included at the end of celmod-collectibles.sp. Each emblem has its own shot style ("fx" in collectibles.txt) and
// its own aura while it is held ("aura"). The styles are built from layers: textured beams (lightning, crystal,
// physics, laser), coloured dots, glows, rings, sparks and short dynamic lights, so emblems of the same family look
// different from each other and not just recoloured.
//
// The game sends at most 32 temporary effects to a player each update, so every style stays well under that.

#if defined _celmod_emblemfx_included
 #endinput
#endif
#define _celmod_emblemfx_included

// Textures, each with a stock fallback in case a server is missing one.
int g_iFxGlow, g_iFxSoftGlow, g_iFxFlame, g_iFxEmber, g_iFxSteam, g_iFxBlueGlow, g_iFxPurpleGlow, g_iFxRedGlow, g_iFxYellowGlow, g_iFxGreenGlow, g_iFxOrangeGlow, g_iFxBlackBall, g_iFxExplosion;
int g_iBmLaser, g_iBmLightning, g_iBmPhys, g_iBmCrystal, g_iBmXBeam, g_iBmBlue, g_iBmShock, g_iBmSpine, g_iBmHalo;

char g_sFxZap[PLATFORM_MAX_PATH], g_sFxBoom[PLATFORM_MAX_PATH], g_sFxSplash[PLATFORM_MAX_PATH], g_sFxGlass[PLATFORM_MAX_PATH], g_sFxPulse[PLATFORM_MAX_PATH], g_sFxThunder[PLATFORM_MAX_PATH];

float g_fNextAura[MAXPLAYERS + 1];
float g_fAuraLast[MAXPLAYERS + 1][3];
float g_fAuraSpin[MAXPLAYERS + 1];

ConVar g_cvAura;

int Fx_PrecacheTexture(const char[] sPath, const char[] sFallback)
{
	char sFile[PLATFORM_MAX_PATH];

	Format(sFile, sizeof(sFile), "materials/%s", sPath);

	return PrecacheModel(FileExists(sFile, true) ? sPath : sFallback, true);
}

void Fx_PrecacheSound(char[] sOut, int iMaxLength, const char[] sPath, const char[] sFallback)
{
	char sFile[PLATFORM_MAX_PATH];

	Format(sFile, sizeof(sFile), "sound/%s", sPath);

	strcopy(sOut, iMaxLength, FileExists(sFile, true) ? sPath : sFallback);

	PrecacheSound(sOut, true);
}

void Fx_Precache()
{
	g_iFxGlow = Fx_PrecacheTexture("sprites/glow04_noz.vmt", "sprites/glow04_noz.vmt");
	g_iFxSoftGlow = Fx_PrecacheTexture("sprites/light_glow03.vmt", "sprites/glow04_noz.vmt");
	g_iFxFlame = Fx_PrecacheTexture("sprites/flamelet1.vmt", "sprites/glow04_noz.vmt");
	g_iFxEmber = Fx_PrecacheTexture("sprites/plasmaember.vmt", "sprites/glow04_noz.vmt");
	g_iFxSteam = Fx_PrecacheTexture("sprites/steam1.vmt", "sprites/glow04_noz.vmt");
	g_iFxBlueGlow = Fx_PrecacheTexture("sprites/blueglow2.vmt", "sprites/glow04_noz.vmt");
	g_iFxPurpleGlow = Fx_PrecacheTexture("sprites/purpleglow1.vmt", "sprites/glow04_noz.vmt");
	g_iFxRedGlow = Fx_PrecacheTexture("sprites/redglow1.vmt", "sprites/glow04_noz.vmt");
	g_iFxYellowGlow = Fx_PrecacheTexture("sprites/yellowglow1.vmt", "sprites/light_glow03.vmt");
	g_iFxGreenGlow = Fx_PrecacheTexture("sprites/greenglow1.vmt", "sprites/glow04_noz.vmt");
	g_iFxOrangeGlow = Fx_PrecacheTexture("sprites/orangeglow1.vmt", "sprites/flamelet1.vmt");
	g_iFxBlackBall = Fx_PrecacheTexture("sprites/strider_blackball.vmt", "sprites/purpleglow1.vmt");
	g_iFxExplosion = Fx_PrecacheTexture("sprites/zerogxplode.vmt", "sprites/flamelet1.vmt");

	g_iBmLaser = Fx_PrecacheTexture("sprites/laserbeam.vmt", "sprites/laserbeam.vmt");
	g_iBmLightning = Fx_PrecacheTexture("sprites/lgtning.vmt", "sprites/laserbeam.vmt");
	g_iBmPhys = Fx_PrecacheTexture("sprites/physbeam.vmt", "sprites/laserbeam.vmt");
	g_iBmCrystal = Fx_PrecacheTexture("sprites/crystal_beam1.vmt", "sprites/laserbeam.vmt");
	g_iBmXBeam = Fx_PrecacheTexture("sprites/xbeam2.vmt", "sprites/laserbeam.vmt");
	g_iBmBlue = Fx_PrecacheTexture("sprites/bluelaser1.vmt", "sprites/laserbeam.vmt");
	g_iBmShock = Fx_PrecacheTexture("sprites/rollermine_shock.vmt", "sprites/lgtning.vmt");
	g_iBmSpine = Fx_PrecacheTexture("sprites/hydraspinalcord.vmt", "sprites/physbeam.vmt");
	g_iBmHalo = Fx_PrecacheTexture("sprites/halo01.vmt", "sprites/glow04_noz.vmt");

	Fx_PrecacheSound(g_sFxZap, sizeof(g_sFxZap), "ambient/energy/zap7.wav", "ambient/energy/zap1.wav");
	Fx_PrecacheSound(g_sFxBoom, sizeof(g_sFxBoom), "ambient/explosions/explode_4.wav", "ambient/explosions/exp2.wav");
	Fx_PrecacheSound(g_sFxSplash, sizeof(g_sFxSplash), "ambient/water/water_splash2.wav", "ambient/water/water_splash1.wav");
	Fx_PrecacheSound(g_sFxGlass, sizeof(g_sFxGlass), "physics/glass/glass_sheet_break1.wav", "physics/glass/glass_impact_bullet4.wav");
	Fx_PrecacheSound(g_sFxPulse, sizeof(g_sFxPulse), "weapons/airboat/airboat_gun_energy1.wav", "ambient/energy/zap1.wav");
	Fx_PrecacheSound(g_sFxThunder, sizeof(g_sFxThunder), "ambient/levels/labs/electric_explosion4.wav", "ambient/levels/labs/electric_explosion1.wav");

	Fx_PrecachePhysical();
}

// Writes a temp entity property only if this game has it, so a missing one can never stop an effect with an error.
void Fx_WriteNum(const char[] sProp, int iValue)
{
	if (TE_IsValidProp(sProp))
	{
		TE_WriteNum(sProp, iValue);
	}
}

void Fx_WriteFloat(const char[] sProp, float fValue)
{
	if (TE_IsValidProp(sProp))
	{
		TE_WriteFloat(sProp, fValue);
	}
}

void Fx_WriteVector(const char[] sProp, const float fValue[3])
{
	if (TE_IsValidProp(sProp))
	{
		TE_WriteVector(sProp, fValue);
	}
}

//Building blocks:
void Fx_Color(int iOut[4], int iR, int iG, int iB, int iA = 255)
{
	iOut[0] = iR;
	iOut[1] = iG;
	iOut[2] = iB;
	iOut[3] = iA;
}

// A colour part of the way towards white (fAmount 0 to 1), for bright cores.
void Fx_Lighter(const int iColor[4], float fAmount, int iOut[4])
{
	for (int i = 0; i < 3; i++)
	{
		iOut[i] = iColor[i] + RoundToFloor((255 - iColor[i]) * fAmount);
	}

	iOut[3] = iColor[3];
}

void Fx_Darker(const int iColor[4], float fAmount, int iOut[4])
{
	for (int i = 0; i < 3; i++)
	{
		iOut[i] = RoundToFloor(iColor[i] * (1.0 - fAmount));
	}

	iOut[3] = iColor[3];
}

void Fx_Hue(float fHue, int iOut[4])
{
	int iRGB[3];

	HSVtoRGB(fHue, 1.0, 1.0, iRGB);

	iOut[0] = iRGB[0];
	iOut[1] = iRGB[1];
	iOut[2] = iRGB[2];
	iOut[3] = 255;
}

void Fx_Beam(const float fA[3], const float fB[3], int iModel, float fWidth, float fEndWidth, float fLife, float fAmplitude, const int iColor[4], int iSpeed = 0, int iFrameRate = 15)
{
	TE_SetupBeamPoints(fA, fB, iModel, g_iBmHalo, 0, iFrameRate, fLife, fWidth, fEndWidth, 1, fAmplitude, iColor, iSpeed);
	TE_SendToAll();
}

void Fx_Ring(const float fCenter[3], float fFrom, float fTo, int iModel, float fWidth, float fLife, float fAmplitude, const int iColor[4])
{
	TE_SetupBeamRingPoint(fCenter, fFrom, fTo, iModel, g_iBmHalo, 0, 15, fLife, fWidth, fAmplitude, iColor, 10, 0);
	TE_SendToAll();
}

void Fx_Glow(const float fPos[3], int iModel, float fScale, float fLife, int iBrightness = 220)
{
	TE_SetupGlowSprite(fPos, iModel, fLife, fScale, iBrightness);
	TE_SendToAll();
}

// A coloured blob of light: a very short, fat beam.
void Fx_Dot(const float fPos[3], const int iColor[4], float fSize, float fLife)
{
	float fA[3], fB[3];

	fA = fPos;
	fB = fPos;

	fA[2] -= fSize * 0.3;
	fB[2] += fSize * 0.3;

	TE_SetupBeamPoints(fA, fB, g_iBmLaser, g_iBmHalo, 0, 15, fLife, fSize, fSize, 1, 0.0, iColor, 0);
	TE_SendToAll();
}

// Lights up the area around a point for a moment.
void Fx_Light(const float fPos[3], const int iColor[4], float fRadius, float fTime, int iExponent = 5)
{
	TE_Start("Dynamic Light");
	Fx_WriteVector("m_vecOrigin", fPos);
	Fx_WriteNum("r", iColor[0]);
	Fx_WriteNum("g", iColor[1]);
	Fx_WriteNum("b", iColor[2]);
	Fx_WriteNum("exponent", iExponent);
	Fx_WriteFloat("m_fRadius", fRadius);
	Fx_WriteFloat("m_fTime", fTime);
	Fx_WriteFloat("m_fDecay", fRadius / fTime);
	TE_SendToAll();
}

void Fx_Sparks(const float fPos[3], const float fDirection[3], int iMagnitude, int iTrail)
{
	TE_SetupSparks(fPos, fDirection, iMagnitude, iTrail);
	TE_SendToAll();
}

// A point part of the way from A to B.
void Fx_Lerp(const float fA[3], const float fB[3], float fT, float fOut[3])
{
	for (int i = 0; i < 3; i++)
	{
		fOut[i] = fA[i] + (fB[i] - fA[i]) * fT;
	}
}

// Two directions at right angles to a line, for spirals and side by side beams.
void Fx_Axes(const float fA[3], const float fB[3], float fForward[3], float fSide[3], float fUp[3])
{
	float fAngles[3];

	MakeVectorFromPoints(fA, fB, fForward);
	NormalizeVector(fForward, fForward);

	GetVectorAngles(fForward, fAngles);
	GetAngleVectors(fAngles, NULL_VECTOR, fSide, fUp);
}

// A spiral wound around the line from A to B, drawn as short beams.
void Fx_Helix(const float fA[3], const float fB[3], float fRadius, float fTurns, int iSegments, float fPhase, int iModel, float fWidth, float fLife, const int iColor[4])
{
	float fForward[3], fSide[3], fUp[3], fLast[3], fPoint[3], fOnLine[3];

	Fx_Axes(fA, fB, fForward, fSide, fUp);

	for (int i = 0; i <= iSegments; i++)
	{
		float fT = float(i) / float(iSegments);
		float fTurn = fPhase + fT * fTurns * 6.2832;

		// The spiral starts tight at the hand and opens up.
		float fR = fRadius * (0.3 + 0.7 * fT);

		Fx_Lerp(fA, fB, fT, fOnLine);

		for (int k = 0; k < 3; k++)
		{
			fPoint[k] = fOnLine[k] + fSide[k] * Cosine(fTurn) * fR + fUp[k] * Sine(fTurn) * fR;
		}

		if (i > 0)
		{
			Fx_Beam(fLast, fPoint, iModel, fWidth, fWidth, fLife, 0.0, iColor);
		}

		fLast = fPoint;
	}
}

// A jagged bolt from A to B.
void Fx_Bolt(const float fA[3], const float fB[3], int iSegments, float fJitter, int iModel, float fWidth, float fLife, const int iColor[4])
{
	float fLast[3], fPoint[3];

	fLast = fA;

	for (int i = 1; i <= iSegments; i++)
	{
		Fx_Lerp(fA, fB, float(i) / float(iSegments), fPoint);

		if (i < iSegments)
		{
			fPoint[0] += GetRandomFloat(-fJitter, fJitter);
			fPoint[1] += GetRandomFloat(-fJitter, fJitter);
			fPoint[2] += GetRandomFloat(-fJitter, fJitter);
		}

		Fx_Beam(fLast, fPoint, iModel, fWidth, fWidth * 0.7, fLife, 0.0, iColor);

		fLast = fPoint;
	}
}

// Beams bursting out of a point in every direction.
void Fx_Starburst(const float fCenter[3], int iCount, float fLength, int iModel, float fWidth, float fLife, const int iColor[4], bool bFlat = false)
{
	float fAngles[3], fDirection[3], fEnd[3];

	for (int i = 0; i < iCount; i++)
	{
		fAngles[0] = bFlat ? GetRandomFloat(-10.0, 10.0) : GetRandomFloat(-80.0, 80.0);
		fAngles[1] = 360.0 * i / iCount + GetRandomFloat(-10.0, 10.0);

		GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

		float fReach = fLength * GetRandomFloat(0.6, 1.0);

		for (int k = 0; k < 3; k++)
		{
			fEnd[k] = fCenter[k] + fDirection[k] * fReach;
		}

		Fx_Beam(fCenter, fEnd, iModel, fWidth, 0.5, fLife, 0.0, iColor);
	}
}

// A sprite that flies to the target with a coloured trail behind it.
void Fx_Missile(int iItem, const float fStart[3], const float fEnd[3], const int iColor[4], float fSpeed, float fScale, bool bGravity, float fTrailWidth, float fTrailLife)
{
	float fA[3], fB[3];
	int iColor2[4];

	fA = fStart;
	fB = fEnd;

	iColor2 = iColor;

	int iSprite = LaunchSprite(iItem, fA, fB, iColor2, fSpeed, fScale, bGravity);

	if (iSprite != -1 && fTrailWidth > 0.0)
	{
		TE_SetupBeamFollow(iSprite, g_iBmLaser, g_iBmHalo, fTrailLife, fTrailWidth, 0.5, 1, iColor2);
		TE_SendToAll();
	}
}

//Physical effects: decals, liquids, splashes, gibs and flames, for emblems made of real stuff.
// Decals (marks left on walls and floors), each only used when the server has it.
int g_iDecalScorch = -1, g_iDecalSmallScorch = -1, g_iDecalCrater = -1, g_iDecalWet = -1, g_iDecalAcid = -1, g_iDecalGlass = -1, g_iDecalGlow = -1;
// Model pieces that burst out of an impact.
int g_iGibIce = -1, g_iGibRock = -1, g_iGibMelon = -1, g_iGibMetal = -1;
// What the shot being drawn hit: 0 the world (decals go on it), a player or prop, or -1 nothing.
int g_iFxShotTarget = -1;

int Fx_PrecacheDecal(const char[] sName)
{
	char sFile[PLATFORM_MAX_PATH];

	Format(sFile, sizeof(sFile), "materials/%s.vmt", sName);

	return FileExists(sFile, true) ? PrecacheDecal(sName, true) : -1;
}

// The first of these models the server has, or -1.
int Fx_PrecacheGib(const char[][] sModels, int iCount)
{
	for (int i = 0; i < iCount; i++)
	{
		if (FileExists(sModels[i], true))
		{
			return PrecacheModel(sModels[i], true);
		}
	}

	return -1;
}

void Fx_PrecachePhysical()
{
	static const char sIce[][] = { "models/gibs/glass_shard01.mdl", "models/gibs/glass_shard02.mdl", "models/props_junk/garbage_glassbottle001a_chunk01.mdl" };
	static const char sRock[][] = { "models/props_debris/concrete_chunk05g.mdl", "models/props_debris/concrete_chunk04a.mdl", "models/props_junk/rock001a.mdl" };
	static const char sMelon[][] = { "models/props_junk/watermelon01_chunk01a.mdl", "models/props_junk/watermelon01_chunk02a.mdl" };
	static const char sMetal[][] = { "models/gibs/metal_gib1.mdl", "models/gibs/metal_gib2.mdl" };

	g_iDecalScorch = Fx_PrecacheDecal("decals/scorch1");
	g_iDecalSmallScorch = Fx_PrecacheDecal("decals/smscorch1");
	g_iDecalCrater = Fx_PrecacheDecal("decals/rollermine_crater");
	g_iDecalWet = Fx_PrecacheDecal("decals/beersplash");
	g_iDecalAcid = Fx_PrecacheDecal("decals/yblood1");
	g_iDecalGlass = Fx_PrecacheDecal("decals/glass/shot1");
	g_iDecalGlow = Fx_PrecacheDecal("decals/redglowfade");

	if (g_iDecalSmallScorch == -1) g_iDecalSmallScorch = g_iDecalScorch;
	if (g_iDecalCrater == -1) g_iDecalCrater = g_iDecalScorch;

	g_iGibIce = Fx_PrecacheGib(sIce, sizeof(sIce));
	g_iGibRock = Fx_PrecacheGib(sRock, sizeof(sRock));
	g_iGibMelon = Fx_PrecacheGib(sMelon, sizeof(sMelon));
	g_iGibMetal = Fx_PrecacheGib(sMetal, sizeof(sMetal));

	PrecacheSound("ambient/fire/ignite.wav", true);
}

// A mark on the wall or floor the shot hit (never floating on a player).
void Fx_Decal(const float fPos[3], int iDecal)
{
	if (iDecal < 0 || g_iFxShotTarget != 0)
	{
		return;
	}

	TE_Start("World Decal");
	Fx_WriteVector("m_vecOrigin", fPos);
	Fx_WriteNum("m_nIndex", iDecal);
	TE_SendToAll();
}

// A coloured spurt of liquid (water, acid, lava) thrown in a direction.
void Fx_Liquid(const float fPos[3], const float fDirection[3], int iR, int iG, int iB, int iAmount)
{
	TE_Start("Blood Stream");
	Fx_WriteVector("m_vecOrigin", fPos);
	Fx_WriteVector("m_vecDirection", fDirection);
	Fx_WriteNum("r", iR);
	Fx_WriteNum("g", iG);
	Fx_WriteNum("b", iB);
	Fx_WriteNum("a", 255);
	Fx_WriteNum("m_nAmount", iAmount);
	TE_SendToAll();
}

// The game's own water splash.
void Fx_Splash(const float fPos[3], float fScale)
{
	if (GetEntityCount() > GetMaxEntities() - 150)
	{
		return;
	}

	int iSplash = CreateEntityByName("env_splash");

	if (iSplash == -1)
	{
		return;
	}

	DispatchKeyValueFloat(iSplash, "scale", fScale);
	DispatchSpawn(iSplash);

	TeleportEntity(iSplash, fPos, NULL_VECTOR, NULL_VECTOR);

	AcceptEntityInput(iSplash, "Splash");

	KillAfter(iSplash, 1.0);
}

// Pieces (ice shards, rubble, melon) bursting out of a point. iFlags: 1 glass sounds, 2 metal, 4 flesh, 8 wood.
void Fx_Gibs(const float fPos[3], int iModel, int iCount, float fSpeed, float fLife, int iFlags)
{
	float fSize[3] = { 16.0, 16.0, 16.0 }, fVelocity[3];

	if (iModel < 0)
	{
		return;
	}

	fVelocity[2] = fSpeed;

	TE_Start("breakmodel");
	Fx_WriteVector("m_vecOrigin", fPos);
	Fx_WriteFloat("m_angRotation[0]", 0.0);
	Fx_WriteFloat("m_angRotation[1]", GetRandomFloat(0.0, 360.0));
	Fx_WriteFloat("m_angRotation[2]", 0.0);
	Fx_WriteVector("m_vecSize", fSize);
	Fx_WriteVector("m_vecVelocity", fVelocity);
	Fx_WriteNum("m_nModelIndex", iModel);
	Fx_WriteNum("m_nRandomization", 100);
	Fx_WriteNum("m_nCount", iCount);
	Fx_WriteFloat("m_fTime", fLife);
	Fx_WriteNum("m_nFlags", iFlags);
	TE_SendToAll();
}

// A short-lived patch of real flames on the ground (it does no damage itself).
void Fx_FirePatch(const float fPos[3], float fSize, float fSeconds)
{
	if (GetEntityCount() > GetMaxEntities() - 150)
	{
		return;
	}

	int iFire = CreateEntityByName("env_fire");

	if (iFire == -1)
	{
		return;
	}

	DispatchKeyValueFloat(iFire, "firesize", fSize);
	DispatchKeyValueFloat(iFire, "health", fSeconds);
	DispatchKeyValue(iFire, "fireattack", "1");
	DispatchKeyValue(iFire, "damagescale", "0");
	DispatchKeyValue(iFire, "spawnflags", "156");

	DispatchSpawn(iFire);

	TeleportEntity(iFire, fPos, NULL_VECTOR, NULL_VECTOR);

	AcceptEntityInput(iFire, "StartFire");

	KillAfter(iFire, fSeconds + 2.0);
}

// A puff of smoke or steam.
void Fx_Puff(const float fPos[3], float fScale)
{
	TE_SetupSmoke(fPos, g_iFxSteam, fScale, 8);
	TE_SendToAll();
}

// A point near the impact, pushed back off the wall a little so effects are not inside it.
void Fx_OffSurface(const float fEnd[3], const float fDirection[3], float fBack, float fOut[3])
{
	for (int i = 0; i < 3; i++)
	{
		fOut[i] = fEnd[i] - fDirection[i] * fBack;
	}
}

//Shot styles, one per emblem:
// True when the style was one of these (the older, simpler styles are still drawn by DrawShotEffect).
// Emblems made of something real (water, fire, ice, acid, earth) use the game's own effects and leave marks where
// they hit; emblems made of light or energy (lasers, gems, plasma, lightning) use beams.
bool DrawStyledShot(int iClient, int iItem, const char[] sFx, float fStart[3], float fEnd[3], float fDirection[3], const int iColor[4])
{
	float fUp[3] = { 0.0, 0.0, 1.0 }, fPoint[3], fHigh[3], fForward[3], fSide[3], fAxisUp[3], fOut[3], fBack[3];
	int iCore[4], iDeep[4], iTint[4];

	Fx_Lighter(iColor, 0.6, iCore);
	Fx_Darker(iColor, 0.5, iDeep);

	float fNormal[3];

	fNormal[0] = -fDirection[0];
	fNormal[1] = -fDirection[1];
	fNormal[2] = -fDirection[2];

	// Just in front of the surface that was hit, for effects that must not start inside the wall.
	Fx_OffSurface(fEnd, fDirection, 6.0, fBack);

	// Out of the surface and a little up: where splashes and debris fly.
	for (int k = 0; k < 3; k++)
	{
		fOut[k] = fNormal[k] + (k == 2 ? 0.6 : 0.0);
	}

	NormalizeVector(fOut, fOut);

	// ---- Water ----
	if (StrEqual(sFx, "waterbolt"))
	{
		// Water: a ball of water that arcs to its target and splashes, leaving it wet.
		Fx_Missile(iItem, fStart, fEnd, iColor, 900.0, 0.4, true, 2.0, 0.25);

		Fx_Splash(fBack, 6.0);
		Fx_Liquid(fBack, fOut, iColor[0], iColor[1], iColor[2], 40);
		Fx_Decal(fEnd, g_iDecalWet);

		PlayShotSound(iClient, SOUND_WATER);
	} else if (StrEqual(sFx, "wave"))
	{
		// Tsunami: a rushing wall of water, spray all along it, crashing down with a big splash.
		for (int i = 1; i <= 3; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 3.5, fPoint);
			fPoint[2] -= 10.0;

			Fx_Liquid(fPoint, fDirection, iColor[0], iColor[1], iColor[2], 60);
		}

		Fx_Splash(fBack, 14.0);
		Fx_Liquid(fBack, fUp, iColor[0], iColor[1], iColor[2], 120);

		fPoint = fEnd;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 10.0, 140.0, g_iBmPhys, 6.0, 0.7, 0.0, iCore);

		Fx_Decal(fEnd, g_iDecalWet);

		PlayShotSound(iClient, g_sFxSplash);
	} else if (StrEqual(sFx, "maelstrom"))
	{
		// Maelstrom: a torrent that turns into a whirlpool where it lands, dragging everything around.
		for (int i = 1; i <= 2; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 2.5, fPoint);

			Fx_Liquid(fPoint, fDirection, iColor[0], iColor[1], iColor[2], 60);
		}

		float fTurn = GetGameTime() * 4.0;

		for (int i = 0; i < 4; i++)
		{
			float fSwirl[3], fAng = fTurn + 1.5708 * i;

			fPoint = fBack;
			fPoint[0] += Cosine(fAng) * 40.0;
			fPoint[1] += Sine(fAng) * 40.0;

			fSwirl[0] = -Sine(fAng);
			fSwirl[1] = Cosine(fAng);
			fSwirl[2] = 0.3;

			Fx_Liquid(fPoint, fSwirl, iColor[0], iColor[1], iColor[2], 50);
		}

		for (int i = 0; i < 3; i++)
		{
			fPoint = fEnd;
			fPoint[2] += 4.0 + i * 16.0;

			Fx_Ring(fPoint, 120.0 - i * 30.0, 10.0, g_iBmPhys, 5.0, 0.6 + i * 0.15, 0.0, i == 1 ? iCore : iColor);
		}

		Fx_Splash(fBack, 10.0);
		Fx_Decal(fEnd, g_iDecalWet);

		PlayShotSound(iClient, g_sFxSplash);
	} else if (StrEqual(sFx, "geyser"))
	{
		// Geyser: the ground bursts open and a column of water shoots straight up.
		Fx_Missile(iItem, fStart, fEnd, iColor, 1200.0, 0.3, false, 2.0, 0.2);

		for (int i = 0; i < 3; i++)
		{
			float fJet[3];

			fJet[0] = GetRandomFloat(-0.15, 0.15);
			fJet[1] = GetRandomFloat(-0.15, 0.15);
			fJet[2] = 1.0;

			Fx_Liquid(fBack, fJet, iColor[0], iColor[1], iColor[2], 160);
		}

		Fx_Splash(fBack, 10.0);
		Fx_Gibs(fBack, g_iGibRock, 4, 300.0, 2.0, 0);
		Fx_Decal(fEnd, g_iDecalWet);

		PlayShotSound(iClient, g_sFxSplash);

	// ---- Acid and poison ----
	} else if (StrEqual(sFx, "acidglob"))
	{
		// Acid: a lobbed glob that splatters, eats into the surface and hisses.
		Fx_Missile(iItem, fStart, fEnd, iColor, 800.0, 0.4, true, 2.0, 0.3);

		Fx_Liquid(fBack, fOut, iColor[0], iColor[1], iColor[2], 50);
		Fx_Puff(fBack, 14.0);
		Fx_Decal(fEnd, g_iDecalAcid);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "venomspiral"))
	{
		// Venom: a spat stream of poison that drips from where it lands.
		for (int i = 1; i <= 3; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 3.5, fPoint);

			Fx_Liquid(fPoint, fDirection, iColor[0], iColor[1], iColor[2], 25);
		}

		Fx_Liquid(fBack, fOut, iDeep[0], iDeep[1], iDeep[2], 60);
		Fx_Glow(fBack, g_iFxGreenGlow, 0.4, 0.4);
		Fx_Decal(fEnd, g_iDecalAcid);

		PlayShotSound(iClient, SOUND_STEAM);

	// ---- Fire ----
	} else if (StrEqual(sFx, "lava"))
	{
		// Magma: a lobbed blob of molten rock that splatters, scorches the ground and leaves it burning.
		Fx_Missile(iItem, fStart, fEnd, iColor, 850.0, 0.7, true, 4.0, 0.5);

		Fx_Liquid(fBack, fOut, 255, 110, 20, 40);
		Fx_FirePatch(fEnd, 32.0, 3.0);
		Fx_Decal(fEnd, g_iDecalScorch);
		Fx_Light(fBack, iColor, 200.0, 0.8, 6);

		PlayShotSound(iClient, SOUND_FIREBALL);
	} else if (StrEqual(sFx, "embers"))
	{
		// Ember: a scatter of small burning embers that leave little burn marks.
		for (int i = 0; i < 3; i++)
		{
			float fTo[3];

			fTo = fEnd;
			fTo[0] += GetRandomFloat(-20.0, 20.0);
			fTo[1] += GetRandomFloat(-20.0, 20.0);
			fTo[2] += GetRandomFloat(-10.0, 10.0);

			Fx_Missile(iItem, fStart, fTo, iColor, GetRandomFloat(1000.0, 1300.0), 0.25, false, 0.0, 0.3);
		}

		Fx_Sparks(fBack, fOut, 2, 3);
		Fx_Decal(fEnd, g_iDecalSmallScorch);

		PlayShotSound(iClient, SOUND_FIRE);
	} else if (StrEqual(sFx, "comet"))
	{
		// Comet: a fireball with a long burning tail that blows a scorched hole where it lands.
		Fx_Missile(iItem, fStart, fEnd, iColor, 1300.0, 0.9, false, 8.0, 0.8);

		TE_SetupExplosion(fBack, g_iFxExplosion, 2.0, 15, 0, 0, 0);
		TE_SendToAll();

		Fx_FirePatch(fEnd, 40.0, 3.0);
		Fx_Decal(fEnd, g_iDecalScorch);
		Fx_Light(fBack, iColor, 280.0, 0.7, 6);

		PlayShotSound(iClient, SOUND_FIREBALL);
	} else if (StrEqual(sFx, "eruption"))
	{
		// Volcano: the ground erupts: an explosion, a crater, and lava bombs raining down all around it.
		TE_SetupExplosion(fBack, g_iFxExplosion, 3.0, 15, 0, 0, 0);
		TE_SendToAll();

		Fx_Liquid(fBack, fUp, 255, 90, 10, 140);
		Fx_Gibs(fBack, g_iGibRock, 6, 450.0, 3.0, 0);
		Fx_Decal(fEnd, g_iDecalCrater);
		Fx_FirePatch(fEnd, 48.0, 4.0);

		for (int i = 0; i < 4; i++)
		{
			float fBomb[3], fAng = GetRandomFloat(0.0, 6.2832), fReach = GetRandomFloat(80.0, 200.0);

			fBomb = fEnd;
			fBomb[0] += Cosine(fAng) * fReach;
			fBomb[1] += Sine(fAng) * fReach;

			// Each bomb lands on whatever is below it.
			float fDown[3];

			fDown = fBomb;
			fDown[2] -= 600.0;
			fBomb[2] += 32.0;

			Handle hTrace = TR_TraceRayFilterEx(fBomb, fDown, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

			if (TR_DidHit(hTrace))
			{
				TR_GetEndPosition(fBomb, hTrace);
			}

			CloseHandle(hTrace);

			Fx_Missile(iItem, fBack, fBomb, iColor, 600.0, 0.5, true, 3.0, 0.4);

			if (i < 2)
			{
				Fx_FirePatch(fBomb, 24.0, 3.0);
			}

			int iSaved = g_iFxShotTarget;

			g_iFxShotTarget = 0;
			Fx_Decal(fBomb, g_iDecalSmallScorch);
			g_iFxShotTarget = iSaved;
		}

		Fx_Light(fBack, iColor, 400.0, 1.0, 7);

		PlayShotSound(iClient, g_sFxBoom);

	// ---- Ice ----
	} else if (StrEqual(sFx, "snowstorm"))
	{
		// Blizzard: a gust of snow and hail that shatters into ice where it hits.
		Fx_Missile(iItem, fStart, fEnd, iCore, 1200.0, 0.35, false, 2.0, 0.3);

		for (int i = 0; i < 4; i++)
		{
			Fx_Lerp(fStart, fEnd, GetRandomFloat(0.2, 0.95), fPoint);

			fPoint[0] += GetRandomFloat(-24.0, 24.0);
			fPoint[1] += GetRandomFloat(-24.0, 24.0);
			fPoint[2] += GetRandomFloat(-16.0, 16.0);

			Fx_Glow(fPoint, g_iFxGlow, GetRandomFloat(0.1, 0.2), GetRandomFloat(0.4, 0.9), 200);
		}

		Fx_Gibs(fBack, g_iGibIce, 5, 200.0, 1.5, 1);
		Fx_Puff(fBack, 10.0);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "frostline"))
	{
		// Frost: a thin freezing ray that frosts over what it touches.
		Fx_Beam(fStart, fEnd, g_iBmCrystal, 2.0, 2.0, 0.3, 0.0, iCore);

		Fx_Gibs(fBack, g_iGibIce, 2, 120.0, 1.0, 1);
		Fx_Glow(fBack, g_iFxBlueGlow, 0.25, 0.5, 220);
		Fx_Decal(fEnd, g_iDecalGlass);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "shards"))
	{
		// Glacier: three spears of ice that meet at the target and burst into shards.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 0; i < 3; i++)
		{
			float fTurn = 6.2832 * i / 3.0;

			for (int k = 0; k < 3; k++)
			{
				fPoint[k] = fStart[k] + fSide[k] * Cosine(fTurn) * 10.0 + fAxisUp[k] * Sine(fTurn) * 10.0;
			}

			Fx_Beam(fPoint, fEnd, g_iBmCrystal, 6.0, 0.5, 0.35, 0.0, i == 0 ? iCore : iColor);
		}

		Fx_Gibs(fBack, g_iGibIce, 8, 280.0, 2.0, 1);
		Fx_Puff(fBack, 16.0);
		Fx_Decal(fEnd, g_iDecalGlass);

		PlayShotSound(iClient, g_sFxGlass);
	} else if (StrEqual(sFx, "permafrost"))
	{
		// Permafrost: a bolt of deep cold that freezes whatever it hits solid, in a cloud of frozen mist.
		Fx_Beam(fStart, fEnd, g_iBmCrystal, 5.0, 3.0, 0.35, 0.0, iCore);
		Fx_Missile(iItem, fStart, fEnd, iCore, 1500.0, 0.5, false, 0.0, 0.0);

		Fx_Gibs(fBack, g_iGibIce, 12, 350.0, 2.5, 1);
		Fx_Puff(fBack, 24.0);
		Fx_Puff(fEnd, 18.0);

		fPoint = fEnd;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 90.0, 6.0, g_iBmCrystal, 8.0, 0.6, 0.0, iCore);
		Fx_Decal(fEnd, g_iDecalGlass);
		Fx_Light(fBack, iColor, 180.0, 0.6);

		PlayShotSound(iClient, g_sFxGlass);

	// ---- Earth and air ----
	} else if (StrEqual(sFx, "sandstorm"))
	{
		// Sandstorm: a scouring blast of sand and grit.
		for (int i = 1; i <= 3; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 3.0, fPoint);

			TE_SetupDust(fPoint, fNormal, 18.0 + i * 6.0, 0.8);
			TE_SendToAll();
		}

		Fx_Gibs(fBack, g_iGibRock, 3, 150.0, 1.5, 0);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "tornado"))
	{
		// Tornado: a twister spinning up out of the target, throwing dust and debris.
		for (int i = 0; i < 4; i++)
		{
			fPoint = fEnd;
			fPoint[2] += i * 40.0;

			Fx_Ring(fPoint, 8.0 + i * 14.0, 30.0 + i * 30.0, g_iBmPhys, 6.0, 0.6, 2.0, iDeep);
		}

		TE_SetupDust(fEnd, fUp, 40.0, 1.2);
		TE_SendToAll();

		Fx_Gibs(fBack, g_iGibRock, 4, 350.0, 2.0, 0);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "mist"))
	{
		// Grey: a cool drifting mist.
		for (int i = 1; i <= 3; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 3.5, fPoint);

			Fx_Puff(fPoint, 10.0 + i * 4.0);
		}

		PlayShotSound(iClient, SOUND_STEAM);

	// ---- Electricity ----
	} else if (StrEqual(sFx, "arc"))
	{
		// Energy: a glowing ember with lightning crackling along its path.
		Fx_Missile(iItem, fStart, fEnd, iColor, 1600.0, 0.5, false, 2.0, 0.2);
		Fx_Beam(fStart, fEnd, g_iBmLightning, 4.0, 4.0, 0.2, 4.0, iColor, 0, 30);

		TE_SetupEnergySplash(fBack, fNormal, false);
		TE_SendToAll();

		Fx_Decal(fEnd, g_iDecalSmallScorch);

		PlayShotSound(iClient, g_sFxZap);
	} else if (StrEqual(sFx, "pulse"))
	{
		// Pulse: dashes of light that get brighter as they reach the target.
		for (int i = 0; i < 4; i++)
		{
			float fT = i / 4.0;

			Fx_Lerp(fStart, fEnd, fT + 0.04, fPoint);
			Fx_Lerp(fStart, fEnd, fT + 0.18, fHigh);

			Fx_Beam(fPoint, fHigh, g_iBmBlue, 3.0 + i * 2.0, 3.0 + i * 2.0, 0.2, 0.0, i == 3 ? iCore : iColor);
		}

		TE_SetupEnergySplash(fBack, fNormal, true);
		TE_SendToAll();

		Fx_Decal(fEnd, g_iDecalSmallScorch);

		PlayShotSound(iClient, g_sFxPulse);
	} else if (StrEqual(sFx, "static"))
	{
		// Static: a jagged, flickering bolt spitting sparks.
		Fx_Bolt(fStart, fEnd, 6, 14.0, g_iBmLightning, 3.0, 0.15, iCore);

		Fx_Sparks(fBack, fOut, 3, 3);
		Fx_Decal(fEnd, g_iDecalSmallScorch);

		PlayShotSound(iClient, g_sFxZap);
	} else if (StrEqual(sFx, "chainspark"))
	{
		// Spark: a chain of sparks jumping from point to point.
		float fLast[3];

		fLast = fStart;

		for (int i = 1; i <= 4; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 4.0, fPoint);

			if (i < 4)
			{
				fPoint[0] += GetRandomFloat(-16.0, 16.0);
				fPoint[1] += GetRandomFloat(-16.0, 16.0);
				fPoint[2] += GetRandomFloat(-10.0, 10.0);
			}

			Fx_Beam(fLast, fPoint, g_iBmShock, 5.0, 3.0, 0.2, 2.0, iColor, 0, 30);

			fLast = fPoint;
		}

		TE_SetupMetalSparks(fBack, fNormal);
		TE_SendToAll();

		Fx_Decal(fEnd, g_iDecalSmallScorch);

		PlayShotSound(iClient, g_sFxZap);
	} else if (StrEqual(sFx, "thunder") || StrEqual(sFx, "tempest"))
	{
		// Thunder: a bolt of lightning out of the sky onto the target, scorching the ground.
		// Tempest: a bigger bolt, and the storm stays overhead (its lightning jumps to others; see the shock power).
		bool bTempest = StrEqual(sFx, "tempest");

		fHigh = fEnd;
		fHigh[2] += 700.0;

		Handle hTrace = TR_TraceRayFilterEx(fEnd, fHigh, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

		if (TR_DidHit(hTrace))
		{
			TR_GetEndPosition(fHigh, hTrace);
		}

		CloseHandle(hTrace);

		Fx_Bolt(fHigh, fEnd, 6, 30.0, g_iBmLightning, bTempest ? 14.0 : 10.0, 0.25, iCore);
		Fx_Bolt(fHigh, fEnd, 4, 40.0, g_iBmLightning, 4.0, 0.2, iColor);

		if (bTempest)
		{
			fPoint = fHigh;
			fPoint[2] -= 20.0;

			Fx_Puff(fPoint, 60.0);
		}

		Fx_Sparks(fBack, fUp, 6, 4);
		Fx_Decal(fEnd, g_iDecalScorch);
		Fx_Light(fEnd, iCore, bTempest ? 500.0 : 400.0, 0.25, 8);

		PlayShotSound(iClient, g_sFxThunder);
	} else if (StrEqual(sFx, "ion"))
	{
		// Ion: a dead straight cyan beam with rungs of charge crackling across it.
		Fx_Beam(fStart, fEnd, g_iBmBlue, 4.0, 4.0, 0.25, 0.0, iColor);

		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		for (int i = 1; i <= 4; i++)
		{
			Fx_Lerp(fStart, fEnd, i / 5.0, fHigh);

			float fTurn = GetRandomFloat(0.0, 6.2832);
			float fA[3], fB[3];

			for (int k = 0; k < 3; k++)
			{
				fA[k] = fHigh[k] + fSide[k] * Cosine(fTurn) * 10.0 + fAxisUp[k] * Sine(fTurn) * 10.0;
				fB[k] = fHigh[k] - fSide[k] * Cosine(fTurn) * 10.0 - fAxisUp[k] * Sine(fTurn) * 10.0;
			}

			Fx_Beam(fA, fB, g_iBmLightning, 2.0, 2.0, 0.2, 3.0, iCore, 0, 30);
		}

		Fx_Decal(fEnd, g_iDecalSmallScorch);

		PlayShotSound(iClient, g_sFxZap);

	// ---- Light ----
	} else if (StrEqual(sFx, "laser"))
	{
		// Laser: a razor-thin bright beam that leaves a glowing burn mark.
		Fx_Beam(fStart, fEnd, g_iBmLaser, 1.5, 1.5, 0.12, 0.0, iCore, 0, 30);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 5.0, 5.0, 0.12, 0.0, iDeep, 0, 30);

		Fx_Sparks(fBack, fOut, 1, 1);
		Fx_Decal(fEnd, g_iDecalGlow);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "gemtwin") || StrEqual(sFx, "gemprism") || StrEqual(sFx, "gemstar") || StrEqual(sFx, "gemorbit"))
	{
		// The gem lasers: a beam cut through the gem, each with its own facets.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		Fx_Beam(fStart, fEnd, g_iBmLaser, 1.5, 1.5, 0.2, 0.0, iCore);

		if (StrEqual(sFx, "gemtwin"))
		{
			// Ruby: two red strands twisting round each other.
			float fPhase = GetGameTime() * 6.0;

			Fx_Helix(fStart, fEnd, 6.0, 2.0, 5, fPhase, g_iBmLaser, 2.5, 0.25, iColor);
			Fx_Helix(fStart, fEnd, 6.0, 2.0, 5, fPhase + 3.1416, g_iBmLaser, 2.5, 0.25, iDeep);
		} else if (StrEqual(sFx, "gemprism"))
		{
			// Emerald: a square-cut prism of four beams.
			for (int i = 0; i < 4; i++)
			{
				float fTurn = 1.5708 * i + 0.7854, fA[3], fB[3];

				for (int k = 0; k < 3; k++)
				{
					float fOffset = fSide[k] * Cosine(fTurn) * 4.0 + fAxisUp[k] * Sine(fTurn) * 4.0;

					fA[k] = fStart[k] + fOffset;
					fB[k] = fEnd[k] + fOffset;
				}

				Fx_Beam(fA, fB, g_iBmCrystal, 2.0, 2.0, 0.2, 0.0, iColor);
			}
		} else if (StrEqual(sFx, "gemstar"))
		{
			// Sapphire: ends in a six pointed star.
			Fx_Beam(fStart, fEnd, g_iBmBlue, 4.0, 2.0, 0.2, 0.0, iColor);

			for (int i = 0; i < 6; i++)
			{
				float fTurn = 6.2832 * i / 6.0 + GetGameTime();

				for (int k = 0; k < 3; k++)
				{
					fPoint[k] = fBack[k] + fSide[k] * Cosine(fTurn) * 20.0 + fAxisUp[k] * Sine(fTurn) * 20.0;
				}

				Fx_Beam(fBack, fPoint, g_iBmLaser, 3.0, 0.5, 0.3, 0.0, iCore);
			}
		} else {
			// Amethyst: crystals spiralling down the beam.
			for (int i = 1; i <= 5; i++)
			{
				float fT = i / 5.5, fTurn = fT * 12.0 + GetGameTime() * 5.0;

				Fx_Lerp(fStart, fEnd, fT, fHigh);

				for (int k = 0; k < 3; k++)
				{
					fPoint[k] = fHigh[k] + fSide[k] * Cosine(fTurn) * 9.0 + fAxisUp[k] * Sine(fTurn) * 9.0;
				}

				Fx_Dot(fPoint, i % 2 ? iCore : iColor, 4.0, 0.35);
			}
		}

		// The gem's glint where it hits, and a small chip of crystal.
		Fx_Glow(fBack, g_iFxGlow, 0.2, 0.3, 255);
		Fx_Gibs(fBack, g_iGibIce, 1, 120.0, 0.8, 1);
		Fx_Decal(fEnd, g_iDecalGlow);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "plasmaflow"))
	{
		// Plasma: a thick, writhing stream with a white-hot core that melts a mark into the wall.
		Fx_Beam(fStart, fEnd, g_iBmPhys, 10.0, 12.0, 0.2, 5.0, iColor, 0, 40);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 3.0, 3.0, 0.2, 0.0, iCore);

		Fx_Glow(fBack, g_iFxPurpleGlow, 0.5, 0.3);
		Fx_Decal(fEnd, g_iDecalScorch);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "prism"))
	{
		// Prism: white light that fans out into a rainbow and meets again at the target.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);
		Fx_Lerp(fStart, fEnd, 0.5, fHigh);

		for (int i = 0; i < 6; i++)
		{
			float fSpread = (i - 2.5) * 6.0, fA[3], fMid[3];

			Fx_Hue(i * 60.0, iTint);

			for (int k = 0; k < 3; k++)
			{
				fA[k] = fStart[k] + fSide[k] * fSpread;
				fMid[k] = fHigh[k] + fSide[k] * fSpread * 3.0;
			}

			Fx_Beam(fA, fMid, g_iBmLaser, 2.5, 2.5, 0.25, 0.0, iTint);
			Fx_Beam(fMid, fEnd, g_iBmLaser, 2.5, 1.0, 0.25, 0.0, iTint);
		}

		Fx_Glow(fBack, g_iFxGlow, 0.3, 0.3, 255);

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "rainbowspray"))
	{
		// Rainbow: a fountain of colour, every drop a different hue.
		Fx_Axes(fStart, fEnd, fForward, fSide, fAxisUp);

		float fHue = GetGameTime() * 200.0;

		for (int i = 0; i < 8; i++)
		{
			float fAlong = GetRandomFloat(40.0, 220.0);

			for (int k = 0; k < 3; k++)
			{
				fPoint[k] = fStart[k] + fForward[k] * fAlong + fSide[k] * GetRandomFloat(-1.0, 1.0) * fAlong * 0.25 + fAxisUp[k] * GetRandomFloat(-1.0, 1.0) * fAlong * 0.2;
			}

			Fx_Hue(fHue + i * 45.0, iTint);
			Fx_Dot(fPoint, iTint, GetRandomFloat(4.0, 8.0), GetRandomFloat(0.3, 0.7));
		}

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "aurora"))
	{
		// Aurora: shimmering curtains of green and violet light hanging along the path.
		for (int i = 0; i < 5; i++)
		{
			Fx_Lerp(fStart, fEnd, (i + 0.5) / 5.0, fPoint);

			fHigh = fPoint;
			fPoint[2] -= 20.0;
			fHigh[2] += 40.0 + 20.0 * Sine(GetGameTime() * 3.0 + i);

			Fx_Hue(120.0 + i * 40.0, iTint);
			Fx_Beam(fPoint, fHigh, g_iBmPhys, 10.0, 2.0, 0.5, 3.0, iTint, 0, 20);
		}

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "nova") || StrEqual(sFx, "supernova"))
	{
		// Nova: a burst of white light that scorches the ground. Supernova: a star going off, leaving a crater.
		bool bSuper = StrEqual(sFx, "supernova");

		TE_SetupExplosion(fBack, g_iFxExplosion, bSuper ? 4.0 : 2.0, 15, 0, 0, 0);
		TE_SendToAll();

		Fx_Starburst(fBack, bSuper ? 8 : 6, bSuper ? 150.0 : 90.0, g_iBmLaser, 4.0, 0.4, iCore);

		fPoint = fEnd;
		fPoint[2] += 4.0;

		Fx_Ring(fPoint, 10.0, bSuper ? 320.0 : 200.0, g_iBmPhys, 10.0, 0.6, 0.0, iColor);

		if (bSuper)
		{
			fHigh = fEnd;
			fHigh[2] += 320.0;

			Fx_Beam(fEnd, fHigh, g_iBmPhys, 40.0, 4.0, 0.6, 0.0, iCore);
			Fx_Gibs(fBack, g_iGibRock, 8, 500.0, 3.0, 0);
		}

		Fx_Decal(fEnd, bSuper ? g_iDecalCrater : g_iDecalScorch);
		Fx_Light(fBack, iColor, bSuper ? 520.0 : 320.0, bSuper ? 0.9 : 0.5, 7);

		PlayShotSound(iClient, g_sFxBoom);

	// ---- Everything else ----
	} else if (StrEqual(sFx, "glitch"))
	{
		// Errors: an error model with a broken, flickering trail of mismatched lines.
		iTint = iColor;

		LaunchModel(iItem, fStart, fEnd, iTint, 1500.0);

		for (int i = 0; i < 3; i++)
		{
			float fA[3], fB[3];

			Fx_Lerp(fStart, fEnd, GetRandomFloat(0.1, 0.9), fA);

			fB = fA;
			fB[0] += GetRandomFloat(-30.0, 30.0);
			fB[1] += GetRandomFloat(-30.0, 30.0);
			fB[2] += GetRandomFloat(-12.0, 12.0);

			Fx_Beam(fA, fB, g_iBmXBeam, GetRandomFloat(2.0, 6.0), 2.0, GetRandomFloat(0.1, 0.3), 0.0, i % 2 ? iColor : iCore);
		}

		Fx_Gibs(fBack, g_iGibMetal, 2, 150.0, 1.0, 2);

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "healbeam") || StrEqual(sFx, "lovebeam"))
	{
		// Medic and Pink: a soft mending beam with a glow on whoever it touches.
		Fx_Beam(fStart, fEnd, g_iBmPhys, 8.0, 8.0, 0.25, 0.0, iColor, 0, 10);
		Fx_Beam(fStart, fEnd, g_iBmLaser, 2.0, 2.0, 0.25, 0.0, iCore);
		Fx_Glow(fBack, StrEqual(sFx, "lovebeam") ? g_iFxPurpleGlow : g_iFxSoftGlow, 0.4, 0.4);

		PlayShotSound(iClient, SOUND_HEAL);
	} else if (StrEqual(sFx, "tractor") || StrEqual(sFx, "gravwell"))
	{
		// Magnitude and Gravitron: a spiralling field of force gripping the target.
		Fx_Helix(fStart, fEnd, 10.0, 3.0, 8, GetGameTime() * 8.0, g_iBmPhys, 3.0, 0.25, iColor);

		fPoint = fEnd;

		Fx_Ring(fPoint, 70.0, 6.0, g_iBmPhys, 5.0, 0.4, 0.0, iCore);

		if (StrEqual(sFx, "gravwell"))
		{
			TE_SetupDust(fEnd, fUp, 30.0, 0.8);
			TE_SendToAll();
		}

		PlayShotSound(iClient, SOUND_SHOCK);
	} else {
		return false;
	}

	return true;
}

//Auras: only a few emblems have one (the "aura" key), so they stand out.
public void Fx_ThinkAuras()
{
	if (!g_cvAura.BoolValue)
	{
		return;
	}

	float fNow = GetGameTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !g_bHoldingGravGun[i] || g_iActiveEmblem[i] == -1 || fNow < g_fNextAura[i])
		{
			continue;
		}

		// Staggered so a server full of emblems does not draw them all on the same tick.
		g_fNextAura[i] = fNow + 0.5 + GetRandomFloat(0.0, 0.15);

		DrawAura(i, g_iActiveEmblem[i]);
	}
}

void DrawAura(int iClient, int iItem)
{
	char sAura[16];
	float fFeet[3], fChest[3], fHead[3], fPoint[3], fHigh[3], fUp[3] = { 0.0, 0.0, 1.0 };
	int iColor[4], iCore[4], iDeep[4], iTint[4];

	strcopy(sAura, sizeof(sAura), g_Items[iItem].sAura);

	if (sAura[0] == '\0' || StrEqual(sAura, "none"))
	{
		return;
	}

	iColor[0] = g_Items[iItem].iBeamColor[0];
	iColor[1] = g_Items[iItem].iBeamColor[1];
	iColor[2] = g_Items[iItem].iBeamColor[2];
	iColor[3] = 255;

	Fx_Lighter(iColor, 0.6, iCore);
	Fx_Darker(iColor, 0.5, iDeep);

	GetClientAbsOrigin(iClient, fFeet);

	fChest = fFeet;
	fChest[2] += 40.0;

	fHead = fFeet;
	fHead[2] += 78.0;

	g_fAuraSpin[iClient] += 1.3;

	float fSpin = g_fAuraSpin[iClient];

	// How far the player moved since the last aura: trails need a little speed to show.
	float fMoved = GetVectorDistance(g_fAuraLast[iClient], fFeet);
	float fLast[3];

	fLast = g_fAuraLast[iClient];
	g_fAuraLast[iClient] = fFeet;

	if (StrEqual(sAura, "flames"))
	{
		// Flickering flames licking up around the body.
		for (int i = 0; i < 3; i++)
		{
			fPoint = fFeet;
			fPoint[0] += GetRandomFloat(-14.0, 14.0);
			fPoint[1] += GetRandomFloat(-14.0, 14.0);
			fPoint[2] += GetRandomFloat(10.0, 60.0);

			Fx_Glow(fPoint, g_iFxFlame, GetRandomFloat(0.2, 0.4), 0.5, 200);
		}

		Fx_Light(fChest, iColor, 90.0, 0.6, 4);
	} else if (StrEqual(sAura, "frost"))
	{
		// Snowflakes drifting down around the player and a frosty ring at their feet.
		for (int i = 0; i < 3; i++)
		{
			fPoint = fHead;
			fPoint[0] += GetRandomFloat(-30.0, 30.0);
			fPoint[1] += GetRandomFloat(-30.0, 30.0);
			fPoint[2] += GetRandomFloat(0.0, 20.0);

			Fx_Glow(fPoint, g_iFxGlow, GetRandomFloat(0.06, 0.12), 1.0, 230);
		}

		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 36.0, 38.0, g_iBmCrystal, 3.0, 0.6, 0.0, iCore);
	} else if (StrEqual(sAura, "drip"))
	{
		// Drops falling off the player, splashing into small ripples.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fChest;
			fPoint[0] += GetRandomFloat(-16.0, 16.0);
			fPoint[1] += GetRandomFloat(-16.0, 16.0);

			fHigh = fPoint;
			fHigh[2] -= 18.0;

			Fx_Beam(fPoint, fHigh, g_iBmPhys, 2.0, 0.5, 0.4, 0.0, iColor);
		}

		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 4.0, 40.0, g_iBmPhys, 2.0, 0.6, 0.0, iColor);
	} else if (StrEqual(sAura, "sparks"))
	{
		// Electricity jumping across the body.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-18.0, 18.0);
		fPoint[1] += GetRandomFloat(-18.0, 18.0);
		fPoint[2] += GetRandomFloat(-30.0, 30.0);

		fHigh = fChest;
		fHigh[0] += GetRandomFloat(-18.0, 18.0);
		fHigh[1] += GetRandomFloat(-18.0, 18.0);
		fHigh[2] += GetRandomFloat(-30.0, 30.0);

		Fx_Beam(fPoint, fHigh, g_iBmLightning, 3.0, 3.0, 0.2, 6.0, iCore, 0, 30);
		Fx_Sparks(fPoint, fUp, 1, 1);
	} else if (StrEqual(sAura, "thunder"))
	{
		// A small storm cloud overhead that now and then drops a spark.
		fPoint = fHead;
		fPoint[2] += 22.0;

		Fx_Glow(fPoint, g_iFxSteam, 0.5, 0.6, 120);

		if (GetRandomInt(0, 2) == 0)
		{
			Fx_Bolt(fPoint, fHead, 3, 6.0, g_iBmLightning, 2.0, 0.15, iCore);
		}
	} else if (StrEqual(sAura, "glint"))
	{
		// Facets of the gem catching the light around the player.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fChest;
			fPoint[0] += GetRandomFloat(-20.0, 20.0);
			fPoint[1] += GetRandomFloat(-20.0, 20.0);
			fPoint[2] += GetRandomFloat(-20.0, 30.0);

			float fA[3], fB[3];

			fA = fPoint;
			fB = fPoint;
			fA[2] -= 5.0;
			fB[2] += 5.0;

			Fx_Beam(fA, fB, g_iBmLaser, 1.0, 1.0, 0.3, 0.0, iCore);

			fA = fPoint;
			fB = fPoint;
			fA[0] -= 5.0;
			fB[0] += 5.0;

			Fx_Beam(fA, fB, g_iBmLaser, 1.0, 1.0, 0.3, 0.0, iColor);
		}
	} else if (StrEqual(sAura, "prism"))
	{
		// Seven coloured lights circling the player.
		for (int i = 0; i < 4; i++)
		{
			float fTurn = fSpin + 6.2832 * i / 4.0;

			fPoint = fChest;
			fPoint[0] += Cosine(fTurn) * 26.0;
			fPoint[1] += Sine(fTurn) * 26.0;
			fPoint[2] += Sine(fTurn * 2.0) * 10.0;

			Fx_Hue(GetGameTime() * 120.0 + i * 90.0, iTint);
			Fx_Dot(fPoint, iTint, 4.0, 0.5);
		}
	} else if (StrEqual(sAura, "smoke"))
	{
		// Puffs of smoke curling up from the player's feet.
		fPoint = fFeet;
		fPoint[0] += GetRandomFloat(-10.0, 10.0);
		fPoint[1] += GetRandomFloat(-10.0, 10.0);
		fPoint[2] += 6.0;

		TE_SetupSmoke(fPoint, g_iFxSteam, GetRandomFloat(10.0, 18.0), 6);
		TE_SendToAll();

		Fx_Ring(fPoint, 20.0, 34.0, g_iBmPhys, 6.0, 0.6, 2.0, iDeep);
	} else if (StrEqual(sAura, "glitch"))
	{
		// Broken lines of colour flickering on and off around the player.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fChest;
			fPoint[0] += GetRandomFloat(-24.0, 24.0);
			fPoint[1] += GetRandomFloat(-24.0, 24.0);
			fPoint[2] += GetRandomFloat(-36.0, 36.0);

			fHigh = fPoint;
			fHigh[0] += GetRandomFloat(-14.0, 14.0);
			fHigh[1] += GetRandomFloat(-14.0, 14.0);

			Fx_Beam(fPoint, fHigh, g_iBmXBeam, GetRandomFloat(2.0, 5.0), 2.0, GetRandomFloat(0.1, 0.25), 0.0, i ? iColor : iCore);
		}
	} else if (StrEqual(sAura, "speed"))
	{
		// Streaks left behind when running, in the emblem's colour.
		if (fMoved > 40.0)
		{
			for (int i = 0; i < 3; i++)
			{
				float fA[3], fB[3];

				fA = fLast;
				fB = fFeet;

				fA[2] += 12.0 + i * 24.0;
				fB[2] += 12.0 + i * 24.0;

				Fx_Beam(fA, fB, g_iBmPhys, 6.0 - i, 1.0, 0.4, 0.0, i == 1 ? iCore : iColor);
			}
		} else {
			Fx_Ring(fFeet, 10.0, 30.0, g_iBmPhys, 3.0, 0.4, 0.0, iColor);
		}
	} else if (StrEqual(sAura, "bolt"))
	{
		// Lightning: crackling yellow bolts trailing behind a running player.
		if (fMoved > 40.0)
		{
			fLast[2] += 36.0;

			fPoint = fFeet;
			fPoint[2] += 36.0;

			Fx_Bolt(fLast, fPoint, 3, 10.0, g_iBmLightning, 4.0, 0.3, iColor);
		}

		Fx_Sparks(fFeet, fUp, 1, 1);
	} else if (StrEqual(sAura, "dust"))
	{
		// Cheetah: dust kicked up by quick feet.
		if (fMoved > 20.0)
		{
			TE_SetupDust(fFeet, fUp, 16.0, 1.0);
			TE_SendToAll();
		}
	} else if (StrEqual(sAura, "float"))
	{
		// Gravity and falling emblems: slow rings rising up the body, as if the air was lifting.
		fPoint = fFeet;
		fPoint[2] += 4.0 + (RoundToFloor(fSpin) % 4) * 18.0;

		Fx_Ring(fPoint, 22.0, 30.0, g_iBmPhys, 3.0, 0.6, 0.0, iColor);
	} else if (StrEqual(sAura, "bounce"))
	{
		// Jump emblems: a springy pulse at the feet.
		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 4.0, 46.0, g_iBmLaser, 4.0, 0.35, 0.0, iColor);
		Fx_Ring(fPoint, 4.0, 26.0, g_iBmLaser, 2.0, 0.25, 0.0, iCore);
	} else if (StrEqual(sAura, "wisp"))
	{
		// Ghostly wisps drifting around the player.
		float fTurn = fSpin;

		fPoint = fChest;
		fPoint[0] += Cosine(fTurn) * 30.0;
		fPoint[1] += Sine(fTurn) * 30.0;
		fPoint[2] += Sine(fTurn * 0.7) * 20.0;

		Fx_Glow(fPoint, g_iFxSoftGlow, 0.25, 0.8, 120);
		Fx_Dot(fPoint, iColor, 3.0, 0.6);
	} else if (StrEqual(sAura, "halo"))
	{
		// A halo above the head, for the healing and protecting emblems.
		fPoint = fHead;
		fPoint[2] += 10.0;

		Fx_Ring(fPoint, 15.0, 16.0, g_iBmLaser, 3.0, 0.65, 0.0, iCore);
	} else if (StrEqual(sAura, "shield"))
	{
		// Armour and resistance: a ring of force around the body.
		Fx_Ring(fChest, 34.0, 36.0, g_iBmPhys, 10.0, 0.65, 0.0, iDeep);
		Fx_Ring(fFeet, 34.0, 36.0, g_iBmPhys, 4.0, 0.65, 0.0, iColor);
	} else if (StrEqual(sAura, "gold"))
	{
		// Precious metal glinting in the light.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-18.0, 18.0);
		fPoint[1] += GetRandomFloat(-18.0, 18.0);
		fPoint[2] += GetRandomFloat(-20.0, 30.0);

		Fx_Glow(fPoint, g_iFxYellowGlow, 0.15, 0.4, 255);
		Fx_Dot(fPoint, iCore, 2.0, 0.4);
	} else if (StrEqual(sAura, "drain"))
	{
		// Dark threads being drawn into the player from around them.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-60.0, 60.0);
		fPoint[1] += GetRandomFloat(-60.0, 60.0);
		fPoint[2] += GetRandomFloat(-30.0, 30.0);

		Fx_Beam(fPoint, fChest, g_iBmSpine, 3.0, 1.0, 0.4, 2.0, iColor);
	} else if (StrEqual(sAura, "demon"))
	{
		// Dark purple flames and a slow, heavy pulse at the feet.
		fPoint = fFeet;
		fPoint[2] += 30.0;

		Fx_Glow(fPoint, g_iFxPurpleGlow, 0.6, 0.6, 160);

		fPoint = fFeet;
		fPoint[2] += 2.0;

		Fx_Ring(fPoint, 50.0, 10.0, g_iBmLaser, 6.0, 0.6, 0.0, iColor);
	} else if (StrEqual(sAura, "radiation"))
	{
		// Nuke: a sickly glow and a warning pulse.
		Fx_Ring(fChest, 10.0, 70.0, g_iBmPhys, 4.0, 0.5, 0.0, iColor);
		Fx_Light(fChest, iColor, 100.0, 0.6, 3);
	} else if (StrEqual(sAura, "vortex"))
	{
		// Portals: a little swirl of the other side, spinning around the player.
		for (int i = 0; i < 2; i++)
		{
			float fTurn = fSpin * 1.5 + 3.1416 * i;
			float fA[3], fB[3];

			fA = fChest;
			fB = fChest;

			fA[0] += Cosine(fTurn) * 26.0;
			fA[1] += Sine(fTurn) * 26.0;
			fB[0] += Cosine(fTurn + 1.2) * 16.0;
			fB[1] += Sine(fTurn + 1.2) * 16.0;
			fB[2] += 10.0;

			Fx_Beam(fA, fB, g_iBmPhys, 4.0, 1.0, 0.5, 0.0, i ? iCore : iColor);
		}
	} else if (StrEqual(sAura, "blink"))
	{
		// Warp: the player's outline flickers as if they could vanish any moment.
		Fx_Glow(fChest, g_iFxSoftGlow, 0.5, 0.15, 160);
		Fx_Ring(fChest, 30.0, 4.0, g_iBmLaser, 3.0, 0.25, 0.0, iColor);
	} else if (StrEqual(sAura, "sun"))
	{
		// Solar: a warm sun glow overhead.
		fPoint = fHead;
		fPoint[2] += 16.0;

		Fx_Glow(fPoint, g_iFxSoftGlow, 0.5, 0.6, 200);
		Fx_Light(fPoint, iColor, 120.0, 0.6, 4);
	} else if (StrEqual(sAura, "eclipse"))
	{
		// Eclipse: a dark disc overhead with a bright corona.
		fPoint = fHead;
		fPoint[2] += 16.0;

		Fx_Glow(fPoint, g_iFxBlackBall, 0.2, 0.6, 255);
		Fx_Ring(fPoint, 9.0, 11.0, g_iBmLaser, 2.0, 0.6, 1.0, iCore);
	} else if (StrEqual(sAura, "embers"))
	{
		// Chaos: embers floating up from the ground.
		for (int i = 0; i < 2; i++)
		{
			fPoint = fFeet;
			fPoint[0] += GetRandomFloat(-30.0, 30.0);
			fPoint[1] += GetRandomFloat(-30.0, 30.0);

			fHigh = fPoint;
			fHigh[2] += GetRandomFloat(30.0, 70.0);

			Fx_Beam(fPoint, fHigh, g_iBmLaser, 2.0, 0.5, 0.6, 0.0, iColor);
		}
	} else if (StrEqual(sAura, "confetti"))
	{
		// Party: confetti in every colour drifting down.
		for (int i = 0; i < 4; i++)
		{
			fPoint = fHead;
			fPoint[0] += GetRandomFloat(-36.0, 36.0);
			fPoint[1] += GetRandomFloat(-36.0, 36.0);
			fPoint[2] += GetRandomFloat(0.0, 24.0);

			Fx_Hue(GetRandomFloat(0.0, 360.0), iTint);
			Fx_Dot(fPoint, iTint, 3.0, 0.8);
		}
	} else if (StrEqual(sAura, "stars"))
	{
		// Midnight: tiny stars twinkling in a dark ring overhead.
		for (int i = 0; i < 3; i++)
		{
			float fTurn = fSpin * 0.4 + 6.2832 * i / 3.0;

			fPoint = fHead;
			fPoint[0] += Cosine(fTurn) * 22.0;
			fPoint[1] += Sine(fTurn) * 22.0;
			fPoint[2] += 12.0;

			Fx_Glow(fPoint, g_iFxGlow, 0.05, 0.6, 255);
		}

		Fx_Dot(fHead, iDeep, 6.0, 0.6);
	} else if (StrEqual(sAura, "rising"))
	{
		// Crimson and similar: sparks of colour rising off the body.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-14.0, 14.0);
		fPoint[1] += GetRandomFloat(-14.0, 14.0);

		fHigh = fPoint;
		fHigh[2] += 50.0;

		Fx_Beam(fPoint, fHigh, g_iBmLaser, 2.0, 0.5, 0.5, 0.0, iColor);
		Fx_Dot(fHigh, iCore, 3.0, 0.4);
	} else if (StrEqual(sAura, "pulse"))
	{
		// Cyan and similar: a soft heartbeat ring around the chest.
		Fx_Ring(fChest, 10.0, 50.0, g_iBmLaser, 4.0, 0.5, 0.0, iColor);
	} else if (StrEqual(sAura, "dusk"))
	{
		// Sunset: two bands of colour, warm above and cool below.
		int iCool[4] = { 120, 60, 160, 255 };

		fPoint = fChest;
		fPoint[2] += 18.0;

		Fx_Ring(fPoint, 28.0, 30.0, g_iBmPhys, 6.0, 0.6, 0.0, iColor);

		fPoint[2] -= 36.0;

		Fx_Ring(fPoint, 28.0, 30.0, g_iBmPhys, 6.0, 0.6, 0.0, iCool);
	} else if (StrEqual(sAura, "code"))
	{
		// Matrix: green streaks raining down around the player.
		for (int i = 0; i < 3; i++)
		{
			fPoint = fHead;
			fPoint[0] += GetRandomFloat(-30.0, 30.0);
			fPoint[1] += GetRandomFloat(-30.0, 30.0);
			fPoint[2] += GetRandomFloat(0.0, 20.0);

			fHigh = fPoint;
			fHigh[2] -= GetRandomFloat(20.0, 50.0);

			Fx_Beam(fPoint, fHigh, g_iBmLaser, 1.5, 1.5, 0.4, 0.0, i ? iColor : iCore);
		}
	} else if (StrEqual(sAura, "crackle"))
	{
		// Phazon: unstable blue energy crackling over the skin.
		Fx_Bolt(fFeet, fHead, 4, 12.0, g_iBmShock, 4.0, 0.2, iColor);
	} else if (StrEqual(sAura, "haze"))
	{
		// 420: a slow green haze.
		fPoint = fHead;
		fPoint[0] += GetRandomFloat(-8.0, 8.0);
		fPoint[1] += GetRandomFloat(-8.0, 8.0);

		TE_SetupSmoke(fPoint, g_iFxSteam, 10.0, 4);
		TE_SendToAll();

		Fx_Dot(fPoint, iColor, 5.0, 0.6);
	} else if (StrEqual(sAura, "void"))
	{
		// Black: a ring of nothing that swallows the light.
		Fx_Ring(fFeet, 40.0, 10.0, g_iBmSpine, 8.0, 0.6, 0.0, iColor);
		Fx_Glow(fChest, g_iFxBlackBall, 0.15, 0.5, 200);
	} else if (StrEqual(sAura, "radiant"))
	{
		// White: a pure, steady glow.
		Fx_Glow(fChest, g_iFxSoftGlow, 0.7, 0.6, 140);
		Fx_Light(fChest, iColor, 80.0, 0.6, 3);
	} else if (StrEqual(sAura, "phase"))
	{
		// Phantom: a green shimmer slipping in and out of sight.
		fPoint = fChest;
		fPoint[2] += GetRandomFloat(-30.0, 30.0);

		Fx_Ring(fPoint, 20.0, 22.0, g_iBmPhys, 3.0, 0.3, 4.0, iColor);
	} else if (StrEqual(sAura, "heart"))
	{
		// Pink and Lifeline: soft rising glows.
		fPoint = fChest;
		fPoint[0] += GetRandomFloat(-12.0, 12.0);
		fPoint[1] += GetRandomFloat(-12.0, 12.0);
		fPoint[2] += 30.0;

		Fx_Glow(fPoint, g_iFxPurpleGlow, 0.2, 0.7, 200);
		Fx_Dot(fPoint, iColor, 4.0, 0.5);
	}

}
